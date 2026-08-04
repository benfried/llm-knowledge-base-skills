# Running the knowledge base on a schedule

This document compares three ways to run the nightly enrichment and weekly wiki
refresh in the cloud, so you can pick one now and re-evaluate later without
re-deriving everything.

- **[Oz](#option-a--oz-current-choice)** — least setup; a hosted scheduler that
  runs the `-cloud` skills. This is the current choice.
- **[Claude-native scheduled routines](#option-b--claude-native-scheduled-routines)**
  — no third-party scheduler; runs inside Claude Code's own cloud.
- **[Self-hosted on GCP](#option-c--self-hosted-on-gcp)** — a container you own,
  triggered by cron. Most control, most ops.

**Why write this down:** Oz is the path of least resistance, but it's a young
platform owned by Warp. If it changes materially or Warp winds it down, the
work needs a new home. The two alternatives below are that fallback, documented
while the details are fresh. None of them lock you in — the skills, the vault,
and the cookie jar are all portable; only the scheduler and its glue differ.

---

## What every option needs

The three platforms differ only in *who runs the cron job and how you feed it
secrets*. The moving parts underneath are identical.

### 1. The vault sync loop (Obsidian Sync)

There is no magic vault mirror. [Obsidian Sync](https://obsidian.md/sync)
(Obsidian's paid hosted service) is the shared source of truth; every runner is
just another client of it via the [headless CLI](https://obsidian.md/help/headless)
(`ob`). Each scheduled run:

1. `ob sync` at the **start** → pulls the latest vault into `~/vault`.
2. Enriches / refreshes wikis / clips.
3. `ob sync` at the **end** → pushes changes back up.
4. Your Mac's Obsidian pulls them down next time it syncs.

The `enrich-notes-loop-cloud` and `refresh-wiki-cloud` skills already do the
start-and-end `ob sync` themselves, so no platform needs extra sync plumbing —
it only needs the `ob` CLI installed and the auth token on disk at
`~/.obsidian-headless/auth_token`.

Requirements this implies, everywhere:
- An **Obsidian Sync subscription** and a vault pointed at your notes.
- The **headless CLI auth token**, provided to the run as a secret.
- `obsidian-headless` (npm, provides `ob`) installed in the environment.

> **Git alternative.** If you'd rather not depend on Obsidian Sync, the vault
> could instead be a private git repo the runner clones/pulls/pushes. That drops
> the Obsidian Sync requirement but commits your notes to git — a different
> tradeoff, and it would mean adapting the `-cloud` skills to `git` instead of
> `ob sync`.

### 2. The clip-link cookie jar (the one Mac-only piece)

clip-link expands link-only bookmarks into web clippings, and for subscriber
pages (Substack, etc.) it needs your browser session cookies at
`~/.config/clip-link/cookies.txt`. **Those cookies can only be minted on your
Mac** — `extract-cookies.py` decrypts them from Chrome using the macOS login
Keychain, which doesn't exist in any Linux cloud box. So in every option below
the pattern is the same:

1. **Extract locally** on the Mac (see
   [../skills/clip-link/references/extract-cookies.py](../skills/clip-link/references/extract-cookies.py)).
2. **Push the jar to the platform's secret store**, and have the scheduled run
   write it to `~/.config/clip-link/cookies.txt` (`chmod 600`) before invoking
   clip-link.
3. **Refresh rarely.** Substack sessions live for months, so re-minting monthly
   is plenty. An expired jar fails *gracefully* — clip-link just leaves the
   bookmark and reports the paywall, exactly as if no jar were present.

To keep step 1–2 hands-off, add a local `launchd` job on the Mac (say weekly)
that re-runs the extractor and pushes the result to whichever secret store your
platform uses. See [Keeping the cookie jar fresh](#keeping-the-cookie-jar-fresh).

If you don't clip paywalled pages, skip the jar entirely — clip-link still
handles public pages and bare bookmarks without it.

### 3. A model

At this workload's scale the model is the cheap part. The nightly run only
touches *new* un-enriched notes (the `enrichedAt` stamp skips the rest), so
after the initial backfill you're processing a handful of notes a day — low
single-digit dollars a month even on the most expensive model.

| Model | Input / Output per 1M tokens | Use for |
| --- | --- | --- |
| `claude-haiku-4-5` | $1 / $5 | Cheapest Claude; fine for tagging, related-note linking, and clipping. |
| `claude-sonnet-5` | $3 / $15 | The weekly wiki synthesis, if you want more headroom. |
| `claude-opus-4-8` | $5 / $25 | The current default here — best quality, negligible extra cost at this volume. |

Two levers that matter more than the tier:
- **Prompt caching.** The tag registry (`tags.md`) plus the enrich-note system
  prompt is a stable prefix reused on every note in a loop. Caching it drops
  that prefix to ~0.1× cost across the whole run.
- **Open-weight option.** Only Oz lets you run a non-Anthropic model (e.g. Kimi
  k2.6), which is cheaper still. The Claude-native path is Claude-only.

---

## Option A — Oz (current choice)

A hosted agent scheduler by Warp. The [setup-oz-automations](../skills/setup-oz-automations/SKILL.md)
skill walks your agent through the whole setup; this section is the overview.

**How it works.** `oz environment create` builds a container from a Docker image,
clones `benfried/llm-knowledge-base-skills`, and runs `--setup-command` hooks on
boot that install `obsidian-headless`, write the auth token, and do the initial
`ob sync`. `oz schedule create` then registers a nightly enrich run and a weekly
wiki run, each pointing at its `-cloud` skill and (as configured) running on
`claude-opus-4-8`. Secrets go in `oz secret`.

- **Effort:** lowest — one skill drives the entire setup.
- **Secrets:** first-class (`oz secret`) — the Obsidian token and the cookie jar
  both belong here.
- **Models:** any Oz offers, including cheaper open-weight ones. Run
  `oz model list` to confirm the exact identifier for whatever you pick.
- **Vendor risk:** the reason this doc exists. Oz is young and third-party; if it
  changes or goes away, move to Option B or C — the skills and vault are
  untouched by the migration.

To set it up, run the setup-oz-automations skill with your agent.

---

## Option B — Claude-native scheduled routines

> ⚠️ **Verified broken as of Aug 2026: do not use this option as written.**
> `api.obsidian.md` sits behind Cloudflare, and Cloudflare rejects the
> Anthropic sandbox's datacenter egress with a bare `HTTP Error 403` — the
> request never reaches Obsidian's application. The token was never the
> problem: the identical token worked from a residential IP while 403ing from
> the sandbox, and `ob login` itself would hit the same edge block.
>
> **How to tell an edge block from a bad credential:** `ob`'s application
> errors come back as HTTP 200 with a JSON `{error}` and print as readable
> messages; a **bare** `HTTP Error 403` means the request was rejected before
> reaching the application. No credential fix helps with the latter.
>
> The section is kept for the routine/environment mechanics (hook, env vars,
> skills discovery), which are correct and reusable on any runner whose egress
> Cloudflare accepts — see the **persistent VM variant** under Option C, which
> is the deployment that actually works.

Claude Code can run **scheduled cloud agents ("routines")** on a cron in
Anthropic's own cloud — no third-party scheduler. This trades away Oz's
open-weight models and dedicated secret store, but removes a vendor from the
stack. Configuration is split across two layers plus the repo.

### Mapping from the Oz setup

| Oz mechanism | Routine equivalent |
| --- | --- |
| `oz secret create OBSIDIAN_AUTH_TOKEN` | **Environment variable** in the routine's cloud-environment settings. ⚠️ No secret store yet — env vars are visible to anyone who can edit that environment. |
| `oz environment create … --setup-command 'npm install -g obsidian-headless'` | **Setup script** on the cloud environment (Ubuntu 24.04, runs as root). Runs once, then the filesystem is snapshotted and reused; re-runs only if you edit it, change network settings, or after ~7 days. |
| `--setup-command 'write auth token'` / `'ob sync-setup && ob sync'` | A **`SessionStart` hook** (below), *not* the setup script — env-var edits don't invalidate the snapshot, so a token baked into the snapshot goes stale on rotation. |
| `--skill "owner/repo:enrich-notes-loop-cloud"` | Skills must live in **`.claude/skills/`** of the cloned repo. The `owner/repo:skill` reference is Oz-only. |
| `oz schedule create --cron … --prompt …` | The **routine** itself (via `/schedule`), pointing at the repo, with a prompt that invokes the cloud skill. |

### What goes where

**Setup script** (cloud-environment UI, one-time, cached) — the heavy install only:

```bash
#!/bin/bash
npm install -g obsidian-headless
```

clip-link's cloud path needs only `curl` + Python stdlib (both present on Ubuntu
24.04), so there's no `pip install` — `cryptography` is only for cookie
*extraction*, which runs on your Mac, never in the cloud.

**`SessionStart` hook** (`.claude/settings.json` in the cloned repo, runs every
firing) — writes the credentials from env vars each run, so rotation is picked
up, and binds the vault so `ob sync` has something to sync. The logic lives in
[../scripts/cloud-session-start.sh](../scripts/cloud-session-start.sh); the hook
is a one-liner that calls it.

The script is guarded throughout and always exits 0: a missing cookie jar or a
`sync-setup` failure degrades gracefully rather than killing the night's run.
It skips `sync-setup` when the vault is already bound, and redacts the
encryption password out of any error it prints. (The cookie jar is multi-line,
so it travels base64-encoded in a single env var and is decoded there.)

> ⚠️ **`ob sync-setup` binds the current working directory when `--path` is
> omitted.** Run it from the wrong folder once and it will bind that folder to
> your notes vault and start uploading its contents into it. This is not
> hypothetical — it happened during setup, dumping a dotfiles tree at a notes
> vault. The script therefore always passes `--path "$HOME/vault"` and
> `--vault "$OBSIDIAN_VAULT_NAME"` explicitly. Don't "simplify" those away.
>
> If it does happen: pause sync in the Obsidian app immediately
> (`obsidian-cli sync off vault=<name>`) to protect the local copy, then
> `ob sync-unlink --path <wrong-dir>` before anything else runs.

**Skills location.** The routine clones a GitHub repo purely to source
`.claude/skills/` and `.claude/settings.json` — separate from your vault, which
still arrives via `ob sync`. This repo keeps its skills under `skills/`, so
`.claude/skills` is a **symlink to `../skills`** — one source of truth, no
duplicated copies to drift apart. Verified: Claude Code discovers all seven
skills through the symlink, `-cloud` variants included.

**Per-run sync** needs no new plumbing — the `-cloud` skill's own `ob sync`
keeps `~/vault` current once the token file exists.

### Consequences to weigh

- **Claude-only models.** Routines run on Claude models — Haiku 4.5 is your
  cheap floor; there's no Kimi/open-weight option here.
- **Secrets are env vars visible to environment editors**, and base64 isn't
  encryption. Both the Obsidian token and the cookie jar sit in the environment
  config in readable form. Fine for a personal setup; note it before sharing the
  environment.

### Checklist

1. Add a **setup script** to the routine's cloud environment: `npm install -g obsidian-headless`.
2. Add **environment variables** — `OBSIDIAN_AUTH_TOKEN`,
   `OBSIDIAN_ENCRYPTION_PASSWORD` (if the vault is end-to-end encrypted, which
   `sync-setup` needs to bind it), and optionally `CLIP_LINK_COOKIES_B64` (the
   jar, base64-encoded), `OBSIDIAN_VAULT_NAME` (defaults to `kb`) and
   `OBSIDIAN_DEVICE_NAME` (defaults to `claude-routine`, and is what shows up in
   sync version history).
3. ~~Add the **`SessionStart` hook**~~ — **done**, see `.claude/settings.json`
   and `scripts/cloud-session-start.sh`. It writes each credential only when its
   env var is set, binds the vault with `--path` pinned, and always exits 0, so a
   missing cookie jar degrades gracefully instead of failing the run.
4. ~~Make the cloud skills discoverable under **`.claude/skills/`**~~ — **done**,
   via the `.claude/skills -> ../skills` symlink.
5. Create the **routine(s)** (`/schedule`). The skills' own recommendation is
   nightly `enrich-notes-loop-cloud` + weekly `refresh-wiki-cloud`; a single
   nightly routine running both back-to-back also works, at the cost of an extra
   `ob sync` round-trip per night.

**Timezone caveat.** Routine crons are **UTC only**, so a fixed expression drifts
an hour across US daylight-saving transitions. `0 6 * * *` is 2am America/New_York
in EDT and 1am in EST. Adjust the cron twice a year, or accept the drift.

---

## Option C — Self-hosted on GCP

Maximum control, no scheduler vendor beyond GCP + Anthropic. Two shapes: a
**persistent VM** (deployed and working — see below) or a container job
(sketched after it).

### Variant C1 — persistent VM (the deployment that works)

An always-on VM you already have (here: `carbonsteel`, Ubuntu, reached via a
gcloud IAP tunnel) sidesteps every credential-transplant problem: there is no
snapshot lifecycle and no env-var secret store, because **every credential is
minted on the VM itself, once, interactively** and persists in the home
directory like on a laptop:

- `ob login` on the VM → its own auth token (nothing copied from another
  machine, nothing to go stale in an env var).
- `ob sync-setup --vault kb --path ~/vault --device-name <host>` once —
  `--path` pinned, per the warning above.
- `claude` login once (subscription OAuth) → persistent CLI credentials.
- Cookie jar `scp`'d to `~/.config/clip-link/cookies.txt` (`chmod 600`).

Nightly runs are a `~/bin/kb-nightly.sh` that pulls this repo, then runs
`claude -p` with the enrich → wiki → run-record prompt, invoked by a **systemd
user timer** (`OnCalendar=*-*-* 02:07:00 America/New_York` — DST-correct on a
UTC box, unlike raw cron) with `Persistent=true` and lingering enabled.

**Before assuming any runner can work, run the egress test from it:**

```sh
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-Type: application/json' -d '{}' https://api.obsidian.md/user/info
# 200 (a JSON app response) = usable; bare 403 = Cloudflare-blocked, stop here.
```

### Variant C2 — container job (sketch, unverified)

### Architecture

```
Cloud Scheduler ──(cron)──▶ Cloud Run Job ──▶ container:
                                               ├─ obsidian-headless (ob sync)
                                               ├─ Claude Code headless / Agent SDK + the skills
                                               └─ reads secrets from Secret Manager
```

- **[Cloud Scheduler](https://cloud.google.com/scheduler)** fires the job on a
  cron (one trigger for nightly enrich, one for weekly wiki).
- **[Cloud Run Jobs](https://cloud.google.com/run/docs/create-jobs)** run the
  container to completion and exit — no idle cost between runs (effectively free
  at this cadence). A small always-on `e2-micro` VM with system `cron` is the
  simpler-but-always-on alternative (~$6–7/mo).
- **[Secret Manager](https://cloud.google.com/secret-manager)** holds the
  Obsidian token, the cookie jar, and your `ANTHROPIC_API_KEY`, mounted into the
  job at runtime.

### Container sketch

```dockerfile
FROM node:22-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl python3 git ca-certificates \
 && npm install -g obsidian-headless @anthropic-ai/claude-code \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY . /app                     # this repo, so the skills are present
ENTRYPOINT ["/app/run.sh"]
```

`run.sh` (the per-run entrypoint):

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Materialize secrets from the mounted Secret Manager volume (or env)
mkdir -p ~/.obsidian-headless ~/.config/clip-link
printf '%s' "$OBSIDIAN_AUTH_TOKEN" > ~/.obsidian-headless/auth_token
printf '%s' "$CLIP_LINK_COOKIES_B64" | base64 -d > ~/.config/clip-link/cookies.txt
chmod 600 ~/.config/clip-link/cookies.txt

# 2. First-run vault setup is idempotent-ish; the skill's own `ob sync` keeps it current
mkdir -p ~/vault && cd ~/vault && ob sync-setup --vault "$OBSIDIAN_VAULT_NAME" || true

# 3. Run the skill headless. $SKILL is set per job (enrich-notes-loop-cloud | refresh-wiki-cloud)
cd /app
claude -p "Run the $SKILL skill." --model "${MODEL:-claude-opus-4-8}"
```

Wire `$SKILL` per Cloud Run Job (two jobs, or one job parameterized by an env
var the two Scheduler triggers set differently).

### Tradeoffs

- **Effort:** highest — you build and maintain the image, the jobs, the
  triggers, and the IAM.
- **Secrets:** proper — Secret Manager with IAM, the strongest handling of the
  three.
- **Models:** any Claude model via `ANTHROPIC_API_KEY`.
- **Vendor risk:** lowest — GCP and the Anthropic API are both durable; nothing
  Oz- or routine-specific to strand you.

---

## Comparison

| | Oz | Claude routines | GCP |
| --- | --- | --- | --- |
| Setup effort | Lowest (one skill) | Medium | Highest |
| Ongoing ops | None | None | You own it |
| Secret handling | `oz secret` | Env vars, visible to env editors | Secret Manager + IAM |
| Model options | Any, incl. open-weight | Claude only | Any Claude |
| Infra to run | None | None | Container + jobs + triggers |
| Vendor risk | Highest (young 3rd party) | Low (Anthropic) | Lowest (GCP + Anthropic) |
| Cookie jar | `oz secret` | base64 env var | Secret Manager |

**Recommendation:** stay on **Oz** while it's convenient. If Oz becomes a
concern, move to **Claude routines** for a no-infra fallback, or **GCP** if you
want full control and the strongest secret handling. The skills, the vault, and
the cookie-jar extractor are identical across all three, so switching is a
scheduler-and-glue change, not a rewrite.

---

## Keeping the cookie jar fresh

The jar is the only piece that must be re-minted on your Mac. Automate it with a
`launchd` agent that re-extracts and re-pushes to whichever secret store the
active platform uses. Sketch:

```sh
# ~/Library/LaunchAgents/dev.clip-link.cookies.plist runs this weekly
python3 /path/to/skills/clip-link/references/extract-cookies.py \
  --profile "$HOME/Library/Application Support/Google/Chrome Dev/Default" \
  --keychain "Chrome Safe Storage" \
  --host substack.com --host <your-other-subscription-domains> \
  --out "$HOME/.config/clip-link/cookies.txt"

# then push to the platform, e.g.:
#   Oz:   oz secret set CLIP_LINK_COOKIES_B64 "$(base64 -i ~/.config/clip-link/cookies.txt)"
#   GCP:  gcloud secrets versions add clip-link-cookies --data-file=$HOME/.config/clip-link/cookies.txt
#   Claude routine: paste the base64 into the environment's CLIP_LINK_COOKIES_B64 var
```

Because sessions are long-lived, a weekly (even monthly) cadence is plenty, and
a missed refresh only degrades clip-link to "leave the bookmark, report the
paywall" until the next run.

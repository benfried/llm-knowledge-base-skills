# LLM knowledge base skills

Agent skills that turn a directory of raw notes — markdown, plain text, or org-mode — into a self-updating knowledge base: tagged and backlinked notes, link-only bookmarks expanded into full web clippings, plus persistent wikis following [Andrej Karpathy's llm-wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

You write things down; agents on a schedule handle the organizing.

## Install

```sh
npx skills add benfried/llm-knowledge-base-skills
```

## The skills

| Skill | What it does |
| --- | --- |
| [clip-link](skills/clip-link/SKILL.md) | Turn a link-only note (a bare URL or lone markdown/org link) into a full web clipping following [Obsidian Web Clipper](https://obsidian.md/clipper) conventions — same frontmatter, same markdown rendering of the page. |
| [enrich-note](skills/enrich-note/SKILL.md) | Enrich one note with topic tags (from a shared [tag registry](skills/enrich-note/references/tags.md)), source attribution, and links to related notes. Handles markdown, plain-text, and org-mode notes. |
| [enrich-notes-loop](skills/enrich-notes-loop/SKILL.md) | Run enrich-note across every un-enriched note in the vault, unattended. Uses an `enrichedAt` frontmatter stamp to skip finished notes. |
| [refresh-wiki](skills/refresh-wiki/SKILL.md) | Maintain every llm-wiki under `wikis/`: ingest new source notes, update entity/concept pages, and lint for stale claims and orphan pages. |
| [enrich-notes-loop-cloud](skills/enrich-notes-loop-cloud/SKILL.md) | enrich-notes-loop wrapped for scheduled cloud runs: sync an Obsidian vault down, enrich, sync back up. |
| [refresh-wiki-cloud](skills/refresh-wiki-cloud/SKILL.md) | refresh-wiki wrapped the same way for scheduled cloud runs. |
| [setup-oz-automations](skills/setup-oz-automations/SKILL.md) | Walks your agent through creating the [Oz](https://oz.dev) environment and schedules that run the cloud skills. |

### Clipping pages behind a login

clip-link can also fill in pages you're subscribed to (Substack and similar). Drop your browser session cookies into `~/.config/clip-link/cookies.txt` (Netscape format, `chmod 600`) and it retries paywalled fetches authenticated, clipping only when the full article comes back. [references/extract-cookies.py](skills/clip-link/references/extract-cookies.py) pulls those cookies out of a Chromium browser on macOS; see the skill for the full flow. The jar is a live credential — keep it out of the vault and any repo.

## Expected vault layout

```
your-vault/
├── raw/       # raw, unfiltered notes — agents read these, never rewrite them
├── wikis/     # generated wikis — agents own this layer
└── tags.md    # the tag registry — seeded by enrich-note on first run
```

Tweak the skills to taste if your layout differs — the enrich loop walks the whole vault (skipping the generated `wikis/` layer), so notes can live in any folders you like (`Clippings/`, `Bookmarks/`, and so on), not just `raw/`. Notes don't have to be markdown: plain-text (`.txt`) and org-mode (`.org`) notes are enriched with their own conventions, and notes that contain only a link get expanded into full web clippings by clip-link.

## Visualizations

Two self-contained HTML apps that build views of your vault in real time. Drop them in the same directory as your notes and open the vault in [Hubble](https://hubble.md), which injects the file-reading runtime they use:

| File | What it shows |
| --- | --- |
| [notes-burndown.html](visualizations/notes-burndown.html) | A GitHub-style activity graph of your notes in `raw/`, with per-day tooltips. |
| [thought-constellation.html](visualizations/thought-constellation.html) | Your notes as a night sky: stars clustered by frontmatter tag (a payoff of enrich-note), related notes linked, click a star to read the note. |

## Running in the cloud

The `-cloud` variants are built for scheduled runners. They assume the environment has synced your vault to `~/vault` with [Obsidian's headless CLI](https://obsidian.md/help/headless), then run enrichment nightly and the wiki refresh weekly.

The quickest path today is [Oz](https://oz.dev): run the setup-oz-automations skill with your agent and it creates the environment and schedules, pulling the skills straight from this repo. But it's not the only option, and Oz is a young third-party platform — so **[docs/cloud-automation.md](docs/cloud-automation.md) documents three ways to run this on a schedule** (Oz, Claude-native scheduled routines, and a self-hosted GCP job), what each needs, how the clip-link cookie jar is handled in each, and how to move between them if one stops being a good fit.

## Read the full walkthrough

These skills started [from Ben Holmes's post on building a self-updating LLM knowledge base](https://bholmes.dev/blog/llm-knowledge-bases/) and have since been customized (multi-format notes, web clipping, and the automation options above).

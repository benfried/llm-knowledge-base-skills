---
name: enrich-notes-loop
description: Enrich every un-enriched note in the vault by running enrich-note over each one. Use to bulk-enrich the vault or auto-tag notes unattended ("while I sleep").
---

# Enrich notes loop

Run the [enrich-note](../enrich-note/SKILL.md) process across the whole vault, one note at a time.

**First run only:** if the vault's tag registry (`tags.md` at the vault root) is missing or still the starter seed, skim the existing notes and flesh it out with the real recurring topics first, so tags are consistent from note one.

Then walk every note in the vault — markdown, plain text, and org-mode (`.md`, `.txt`, `.org`), in whatever folders the vault uses — skipping generated layers like `wikis/`. Enrich each note that has no done-stamp (`enrichedAt` in frontmatter, or `#+enriched_at:` for org notes). Skip notes already stamped — that's how you know what's left.

Also skip, permanently and without stamping:

- **The `Private/` folder** — if a `Private/` folder exists at the vault root, nothing under it is ever read, enriched, clipped, or stamped. It's the user's space for notes that are just notes; agents keep out entirely.
- **Notes flagged `private`** — same treatment for any note carrying a `private` tag (inline or frontmatter), wherever it lives. The flag is the user's (see the vault `tags.md` Flags section); never add or remove it.
- **`tags.md`** — it's the tag registry this process *reads*, not a note; enriching it would be circular.
- **Vault scaffolding** — Obsidian's starter `Welcome.md` and the like: boilerplate with no knowledge content.
- **Parked bookmarks** — link-only notes with `clipParked: true` in frontmatter. Don't re-fetch and don't stamp; they're waiting for [clip-link-browser](../clip-link-browser/SKILL.md) or a human. Do list them once, in one line, in the run's final report ("parked: N — <note names>") so they stay visible without burning a retry.
- **Media-only links** — bookmarks whose URL can never yield an article (Google Photos and other photo/video share links, image hosts). Permanently out of scope: park them on sight (`clipParked: true`, `lastClipError: "media-only link"`) instead of retrying a clip that cannot exist.

Link-only notes whose fetch fails (paywall, JS-only shell, bot block, 404) are left as bookmarks per clip-link's rule — but record the failure with clip-link's §6 bookkeeping (`clipAttempts`/`lastClipError`/`lastClipTry`), which parks the note automatically after 5 identical failures instead of retrying forever.

If a note is link-only (just a URL or a lone link), run [clip-link](../clip-link/SKILL.md) on it first — [clip-youtube](../clip-youtube/SKILL.md) if it's a YouTube video — then enrich the clipping it produces.

This runs unattended: keep going until every note is enriched. Don't delete anything.

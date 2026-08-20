---
name: enrich-notes-loop
description: Enrich every un-enriched note in the vault by running enrich-note over each one. Use to bulk-enrich the vault or auto-tag notes unattended ("while I sleep").
---

# Enrich notes loop

Run the [enrich-note](../enrich-note/SKILL.md) process across the whole vault, one note at a time.

**First run only:** if the vault's tag registry (`tags.md` at the vault root) is missing or still the starter seed, skim the existing notes and flesh it out with the real recurring topics first, so tags are consistent from note one.

Then walk every note in the vault — markdown, plain text, and org-mode (`.md`, `.txt`, `.org`), in whatever folders the vault uses — skipping generated layers like `wikis/`. Enrich each note that has no done-stamp (`enrichedAt` in frontmatter, or `#+enriched_at:` for org notes). Skip notes already stamped — that's how you know what's left.

Also skip, permanently and without stamping:

- **`tags.md`** — it's the tag registry this process *reads*, not a note; enriching it would be circular.
- **Vault scaffolding** — Obsidian's starter `Welcome.md` and the like: boilerplate with no knowledge content.
- **Link-only notes whose fetch fails** (paywall, JS-only shell, 404) — leave them as bookmarks per clip-link's rule; they'll be retried naturally on a later run.

If a note is link-only (just a URL or a lone link), run [clip-link](../clip-link/SKILL.md) on it first — [clip-youtube](../clip-youtube/SKILL.md) if it's a YouTube video — then enrich the clipping it produces.

This runs unattended: keep going until every note is enriched. Don't delete anything.

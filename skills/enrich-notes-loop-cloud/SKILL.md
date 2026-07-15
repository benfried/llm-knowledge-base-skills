---
name: enrich-notes-loop-cloud
description: Run enrich-notes-loop unattended in a cloud sandbox against an Obsidian Sync vault, syncing before and after. Use for scheduled cloud runs.
---
# Enrich notes loop (cloud)

The vault is synced to `~/vault` by the environment setup. Run the [enrich-notes-loop](../enrich-notes-loop/SKILL.md) process against it, wrapped in a sync.

## 1. Pull the latest vault

```sh
cd ~/vault
ob sync-config --file-types image,audio,video,pdf,unsupported
ob sync
```

## 2. Enrich

Run [enrich-notes-loop](../enrich-notes-loop/SKILL.md) with `~/vault` as the vault root. Enrich every note without a done-stamp (`enrichedAt`, or `#+enriched_at:` for org notes), preserving existing note content.

Link-only notes get expanded into web clippings as part of this, which needs network egress from the sandbox — and, for subscriber-only pages, the clip-link cookie jar at `~/.config/clip-link/cookies.txt` (see [docs/cloud-automation.md](../../docs/cloud-automation.md) for how each platform supplies it). Without the jar, paywalled bookmarks are left untouched rather than half-clipped, so a missing jar degrades gracefully.

## 3. Push results back

```sh
cd ~/vault
ob sync
```

If sync reports conflicts or an authentication/setup error at any point, **stop and report the issue** rather than making further edits. Never delete notes or attachments.

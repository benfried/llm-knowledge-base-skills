---
name: clip-youtube
description: Turn a link-only note pointing at a YouTube video into a transcript clipping — Web Clipper-style frontmatter plus the video's transcript rendered as readable, timestamped markdown. Use when asked to clip, expand, or fill in YouTube bookmarks or video links.
---
# Clip YouTube

Turn a note that is only a YouTube link into a transcript clipping: the same frontmatter conventions as [clip-link](../clip-link/SKILL.md), with the video's transcript as the body. Works on one note by path, or sweeps a folder when given one — clip every YouTube link-only note it contains.

Requires `yt-dlp`. Install with `brew install yt-dlp` on macOS, `pipx install yt-dlp` (or `python3 -m pip install -U yt-dlp`) on Linux — avoid the apt package, which lags too far behind YouTube's changes to keep working. If yt-dlp starts failing with extraction errors, update it first (`yt-dlp -U`, or re-run the installer) before debugging anything else.

## 1. Recognize a YouTube link-only note

A note qualifies when, ignoring frontmatter and blank lines, its whole content is a single link (bare URL, markdown link, or org-mode link — clip-link's rule) **and** the URL is a YouTube video:

- `https://www.youtube.com/watch?v=VIDEO_ID`
- `https://youtu.be/VIDEO_ID`
- `https://www.youtube.com/shorts/VIDEO_ID` or `/live/VIDEO_ID`

Extract the 11-character video ID; ignore extra query params (`t=`, `list=`, `si=`). Channel, playlist, and search URLs are not videos — leave those to clip-link. A note with real prose is **not** link-only — leave it alone.

## 2. Check for an existing clipping first

Before fetching, grep the vault for the **video ID** (not the full URL — the same video appears as both `youtu.be/ID` and `watch?v=ID`). If a note's `source:` frontmatter already carries that ID, **do not re-clip**: leave the bookmark untouched and report the duplicate.

## 3. Fetch metadata and captions

Fetch metadata and manually-authored captions in one call, into a temp directory:

```sh
yt-dlp --skip-download --write-info-json --write-subs \
  --sub-langs "en,en-orig" --sub-format "vtt" \
  -o "clip" "https://www.youtube.com/watch?v=$VIDEO_ID"
```

If no subtitle file was written, the video has no manual captions — retry with `--write-auto-subs` in place of `--write-subs` to get YouTube's auto-generated track.

Keep `--sub-langs` to specific tracks; a wildcard like `"en.*"` also requests machine-translated variants and can trip YouTube's rate limiting (HTTP 429). If the video is in another language and has no English track, take the original-language track instead and note that in your report.

From `clip.info.json`, collect for the frontmatter and body: `title`, `channel` (fall back to `uploader`), `upload_date`, `description`, `duration_string`, `webpage_url`, and `chapters` if present.

## 4. Convert the transcript to markdown

Captions are not prose — render them into a transcript a person would want to read:

- **Deduplicate** auto-caption artifacts: the rolling-window format repeats each line across cues; keep each line once, in order.
- **Reflow into paragraphs.** Merge cue fragments into sentences and group them into paragraphs at natural topic pauses (roughly every 30–90 seconds of speech). Strip cue styling, `(applause)`-style noise tags only if they add nothing, and mid-word cue breaks.
- **Timestamp each paragraph.** Prefix each paragraph with a link into the video: `**[3:41](https://www.youtube.com/watch?v=VIDEO_ID&t=221s)**` using the paragraph's first cue time.
- **Use chapters as headings.** If the metadata has `chapters`, make each one a `###` heading at its start time and place paragraphs under the chapter they fall in.
- Reproduce the speech faithfully — this is a transcript, not a summary. Fix nothing beyond punctuation, capitalization, and obvious auto-caption mishearings you are certain of; don't condense or annotate.

## 5. Write the clipping

Replace the note's content with clip-link's frontmatter followed by the body. Keys always appear, in this order, left blank when unknown — never invented:

```md
---
title: "Video Title"
source: "https://www.youtube.com/watch?v=VIDEO_ID"
author:
  - "[[Channel Name]]"
published: 2024-05-01
created: 2026-08-20
description: "First paragraph of the video description."
summary: "Two or three sentences summarizing what the video actually covers, written from the transcript."
tags:
  - "clippings"
  - "youtube"
---
## Description

The full video description, with bare URLs made into links…

## Transcript

**[0:00](https://www.youtube.com/watch?v=VIDEO_ID&t=0s)** First paragraph of the transcript…
```

- `source` is the canonical `webpage_url`; `published` is `upload_date` as `YYYY-MM-DD`; `created` is today.
- `description` is the first paragraph of the video description; skip the `## Description` section entirely if the description is empty or pure link spam.
- `summary` is yours to write, from the transcript: two or three sentences on what the video actually covers and concludes. This is the one place the skill summarizes rather than transcribes — keep it factual, no evaluation. (Unlike other keys, it's never blank: if you have a transcript, you can write it.)
- Merge, don't clobber: carry over any frontmatter the bookmark already had; add `clippings` and `youtube` to its tags rather than replacing them.
- Inline `#tags` count too: if the original note body had tags typed next to the link (e.g. a workflow flag like `#acm-queue`), move each one into the frontmatter tag list before replacing the body. Replacing the body must never lose a tag the user typed. The vault `tags.md` Flags section may define shorthands (e.g. `queue` for `acm-queue`) — write the canonical form to frontmatter, not the shorthand.

File handling follows clip-link: overwrite in place, keep a human-readable filename, otherwise rename to the video title with filename-illegal characters (`\ / : * ? " < > |`) replaced.

## 6. Cloud runners and bot checks

This skill also runs on cloud VMs (the `-cloud` sweep variants), and YouTube treats datacenter IPs with suspicion: fetches that work fine from a home machine can fail there with `Sign in to confirm you're not a bot` or immediate 429s. When that happens and a cookie jar exists at `~/.config/clip-link/cookies.txt` (the clip-link jar — it can carry `youtube.com` cookies too), retry authenticated:

```sh
yt-dlp --cookies ~/.config/clip-link/cookies.txt --skip-download …
```

Same hygiene rules as clip-link: the jar is a live credential — never copy it into the vault, a repo, or your output, and on cloud runs supply it from a platform secret rather than extracting it there. If there's no jar or the retry still fails, treat it as a failed fetch (§7).

## 7. When the fetch fails

No captions in any language, private/deleted video, age-restriction wall, an unresolved bot check, or persistent HTTP 429: **leave the note exactly as it was** and report the URL and the failure. On a 429 specifically, stop sweeping — further fetches will make it worse; tell the user to retry later. A link-only note is still a bookmark; a broken half-clipping is worse.

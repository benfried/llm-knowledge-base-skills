---
name: clip-link
description: Turn a link-only note (a bare URL or a lone markdown/org link) into a full web clipping matching Obsidian Web Clipper conventions — same frontmatter, same markdown rendering of the page. Use when asked to clip, expand, or fill in bookmark or link notes.
---
# Clip link

Turn a note that is only a link into the clipping the [Obsidian Web Clipper](https://obsidian.md/clipper) would have produced. Works on one note by path, or sweeps a folder when given one — clip every link-only note it contains.

## 1. Recognize a link-only note

A note qualifies when, ignoring frontmatter and blank lines, its whole content is a single link:

- a bare URL — `https://example.com/post`
- a markdown link — `[Some title](https://example.com/post)`
- an org-mode link — `[[https://example.com/post][Some title]]`

A stray word or two around the link is fine. A note with real prose is **not** link-only — leave it alone.

## 2. Check for an existing clipping first

Before fetching, grep the vault's frontmatter for a `source:` matching the URL (ignore a trailing-slash difference). If a clipping already exists, **do not re-clip**: leave the bookmark note untouched and report the duplicate so the user can decide whether to delete the redundant bookmark.

## 3. Fetch and convert

Fetch the raw HTML (a web-fetch tool is fine for reading, but pull the real HTML for a faithful conversion):

```sh
curl -sL -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" "$URL"
```

Extract the main article the way a readability extractor would — drop navigation, sidebars, subscribe prompts, footers, comments — and convert it to markdown the way the Web Clipper does:

- Keep the article's heading structure (`##`, `###`, …); don't repeat the page title as a body heading unless the article body itself did.
- Preserve inline links, emphasis, lists, tables, blockquotes, and code blocks.
- Keep images as remote references: `![](https://…)`, with relative URLs resolved to absolute. Keep figure captions as adjacent italic lines.
- Reproduce the content faithfully and completely — this is a clipping, not a summary. Don't editorialize, condense, or annotate.

While you have the HTML, collect metadata for the frontmatter: `<title>`/`og:title`, author (meta tags, byline, JSON-LD), `article:published_time` or a visible publish date, and the meta/`og:description`.

## 4. Write the clipping

Replace the note's content with Web Clipper frontmatter followed by the markdown body. Keys always appear, in this order, left blank when unknown — never invented:

```md
---
title: "Page Title"
source: "https://example.com/post"
author:
  - "[[Author Name]]"
published: 2026-01-15
created: 2026-07-15
description: "The page's meta description."
tags:
  - "clippings"
---
Article body…
```

- `author` is a list of wikilinked names; leave the key empty (`author:`) when there's no identifiable author. Same for `published` and `description`.
- `created` is today's date.
- Merge, don't clobber: if the link note already had frontmatter (tags, notes-to-self), carry those fields over; add `clippings` to its tags rather than replacing them.

File handling: overwrite the note in place and keep it in its folder. Keep its filename if it's already human-readable; if it's a raw URL or slug, rename to the page title with filename-illegal characters (`\ / : * ? " < > |`) replaced — the Web Clipper's naming rule.

## 5. Paywalls the user has access to

Some sources are paywalled but the user has an account (Substack subscriptions, for instance). clip-link reads session cookies from a Netscape-format jar at `~/.config/clip-link/cookies.txt` (`chmod 600`). When a fetch comes back paywalled or truncated and that jar exists, retry with it and re-check:

```sh
curl -sL -b ~/.config/clip-link/cookies.txt -A "Mozilla/5.0 …" "$URL"
```

A Substack post is fully unlocked when the `"isAccessibleForFree":"False"` marker **and** the "This post is for paid subscribers" tail are both gone from the retried HTML. The full article sits in `<div class="available-content">…</div>`. If it's still truncated, treat it as a failed fetch (§6). Substack's per-publication session cookie is `connect.sid` on the custom domain (e.g. `newsletter.pragmaticengineer.com`); the master account cookie is `substack.sid` on `.substack.com` — include both in the jar.

**Populating the jar from a browser (macOS).** Cookies in a signed-in Chromium browser are AES-encrypted with a key in the login Keychain. [references/extract-cookies.py](references/extract-cookies.py) decrypts them into the jar. First, map the account email to its profile directory (Chrome keeps one dir per account, and `Default` is not always the right one):

```sh
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));[print(k,v.get("user_name")) for k,v in d["profile"]["info_cache"].items()]' \
  "$HOME/Library/Application Support/Google/Chrome Dev/Local State"
```

Then extract (the Keychain service is `Chrome Safe Storage` for every Chrome channel — Dev included; Brave/Chromium use their own name). The first run pops a macOS Keychain prompt the user must approve:

```sh
python3 references/extract-cookies.py \
  --profile "$HOME/Library/Application Support/Google/Chrome Dev/<Profile Dir>" \
  --keychain "Chrome Safe Storage" \
  --host substack.com --host pragmaticengineer.com \
  --out "$HOME/.config/clip-link/cookies.txt"
```

Session cookies expire; if authenticated fetches start hitting the paywall again, re-run the extractor to refresh the jar.

Cookie hygiene: the jar is a credential. Never copy it — or any cookie value — into the vault, a repo, or your output; only send a cookie to the site that issued it. For scheduled cloud runs there's no browser or Keychain: supply the jar from a platform secret during environment setup instead of extracting it there.

## 6. When the fetch fails

Paywall you can't unlock, JS-only shell, bot block, 404: **leave the note exactly as it was** and report the URL and the failure. A link-only note is still a bookmark; a broken half-clipping is worse.

---
name: clip-link-browser
description: Sweep parked bookmarks (clipParked) through the user's real, logged-in browser and clip the ones a plain fetch can't reach — bot blocks, Cloudflare Turnstile, login-gated pages. Interactive, macOS + Chrome only. Use when asked to clip parked or blocked bookmarks, or run a browser-assisted catchup.
---

# Clip link (browser-assisted)

The interactive companion to [clip-link](../clip-link/SKILL.md). clip-link's plain
fetches fail on a whole class of URLs that open fine in a real browser: bot
blocks keyed on TLS fingerprints (Reddit, Akamai-fronted sites), Cloudflare
Turnstile (OpenReview), and paywalls whose session lives only in the browser.
After 5 identical failures clip-link parks such bookmarks (`clipParked: true`).
This skill sweeps them through the user's actual logged-in Chrome, where those
defenses pass, and writes the clippings clip-link couldn't.

Interactive by design: it drives the user's real browser session and may need a
one-time menu click or a human step (a consent page, a "claim free post" gate).
Never run it from an unattended loop.

## Preconditions (macOS + Chrome)

1. **"Allow JavaScript from Apple Events"** must be enabled in the target
   Chrome: menu **View → Developer → Allow JavaScript from Apple Events**. If
   the probe below errors, ask the user for that one click (they can turn it
   back off after the sweep):

   ```sh
   osascript -e 'tell application "Google Chrome Dev" to execute front window'\''s active tab javascript "1+1"'
   ```

2. The right profile window is frontmost — tabs open in the **front** window,
   so the logged-in profile (personal, not a work profile) should own it.

## The sweep

1. **Collect targets.** Grep the vault for `clipParked: true` frontmatter (plus
   any URL the user names). Skip `lastClipError: "media-only link"` notes —
   parked-forever is their correct end state; report them as such.

2. **Fetch the rendered DOM** with
   [references/chrome-fetch.sh](references/chrome-fetch.sh):

   ```sh
   references/chrome-fetch.sh "$URL" /tmp/page.html 6   # CHROME_APP overrides the browser
   ```

   It opens a tab, waits for load plus a settle delay (JS-heavy pages render
   after onload — give Reddit/SPA pages 6–10s), dumps `outerHTML`, closes the
   tab. Sanity-check the capture before converting: the real `<title>`, not
   "Prove your humanity" / "Just a moment…" — a captcha page means the user
   should open the URL once by hand and click through, then re-fetch.

3. **Prefer the cleanest content source.** The rendered DOM is the fallback;
   sometimes the browser visit unlocks something better:
   - A Cloudflare-cleared site plants `cf_clearance` in the profile. Extract it
     (clip-link §5's `extract-cookies.py`, `--host <site>`, to a **temp** jar)
     and curl the canonical asset — e.g. an OpenReview paper PDF — with a UA
     matching the browser's. Delete the temp jar afterwards.
   - A Substack "claim my free post" gate needs one human click; after it, add
     the domain to the persistent jar's `--host` list and plain clip-link works
     from then on.

4. **Convert and write** the clipping exactly per clip-link's conventions
   (frontmatter, faithful markdown, merge-don't-clobber). On success remove the
   `clipParked` / `clipAttempts` / `lastClipError` / `lastClipTry` keys, then
   enrich per [enrich-note](../enrich-note/SKILL.md). On failure leave the
   bookkeeping as it was and report why.

5. **Report** per note: clipped, still-blocked (and what human step would
   unblock it), or permanently out of scope.

Cookie hygiene applies unchanged: jars and cookie values never go into the
vault, the repo, or your output; a cookie is only ever sent to the site that
issued it.

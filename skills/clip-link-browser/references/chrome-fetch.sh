#!/usr/bin/env bash
# Fetch a URL's rendered DOM through the user's real, logged-in Chrome session.
#
# Usage: chrome-fetch.sh <url> <outfile> [settle-seconds]
#   CHROME_APP=<AppleScript app name> overrides the browser (default: Google Chrome Dev).
#
# Requires: View > Developer > "Allow JavaScript from Apple Events" enabled in
# that Chrome. Opens a tab, waits for the page to finish loading plus a settle
# delay (JS-heavy pages render after onload), dumps outerHTML, closes the tab.
set -u
URL=$1; OUT=$2; SETTLE=${3:-4}
APP=${CHROME_APP:-Google Chrome Dev}
osascript - "$URL" "$SETTLE" "$APP" <<'AS' > "$OUT"
on run argv
  set theURL to item 1 of argv
  set settle to (item 2 of argv) as integer
  set appName to item 3 of argv
  tell application appName
    set w to front window
    set t to make new tab at end of tabs of w with properties {URL:theURL}
    repeat 90 times
      delay 1
      if loading of t is false then exit repeat
    end repeat
    delay settle
    set h to execute t javascript "document.documentElement.outerHTML"
    close t
    return h
  end tell
end run
AS

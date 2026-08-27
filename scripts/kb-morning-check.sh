#!/usr/bin/env bash
#
# Morning check for the nightly KB run — Mac side.
#
# The nightly runner (on whatever machine runs it; currently this Mac, via
# the com.benfried.kb-nightly launchd agent against the headless vault copy
# at ~/vault) appends one line per run to wikis/kb/log.md under
# "## Run history", and
# Obsidian Sync carries that line to every device. This script, fired by a
# launchd agent each morning, reads the newest line and raises a macOS
# notification: the summary when last night's run landed, an alert when it
# didn't. The vault itself is the transport — no credentials, no extra
# services, and it works no matter which machine ran the loops.
#
# Freshness is judged by AGE (default: anything under 30h counts), not by
# matching today's date — so a Mac that wakes late still reports correctly.
#
# Caveat this script is honest about: the line still arrives via Obsidian
# Sync — the nightly writes it to the headless copy at ~/vault and its final
# `ob sync` pushes it; this script reads the app-managed vault, which only
# pulls while Obsidian.app runs. A MISSING alert can therefore mean "the
# headless push failed" or just "the app hasn't pulled yet"; the alert says so.

set -u

LOG="${KB_VAULT_LOG:-$HOME/kb/kb/wikis/kb/log.md}"
MAX_AGE_HOURS="${KB_MAX_AGE_HOURS:-30}"

notify() { # title, body, sound
  /usr/bin/osascript - "$1" "$2" "$3" <<'AS' >/dev/null 2>&1
on run argv
  display notification (item 2 of argv) with title (item 1 of argv) sound name (item 3 of argv)
end run
AS
}

if [ ! -f "$LOG" ]; then
  notify "KB nightly: vault log missing" "No file at $LOG - is the vault present on this Mac?" "Basso"
  exit 0
fi

# Newest "- YYYY-MM-DD HH:MM UTC - ..." line under the Run history heading.
line=$(awk '/^## Run history/{f=1;next} f&&/^- [0-9]/{l=$0} END{print l}' "$LOG")

if [ -z "$line" ]; then
  notify "KB nightly: NO RUN RECORD" "log.md has no Run history entries. Check the runner: launchctl print gui/\$(id -u)/com.benfried.kb-nightly and ~/kb-logs/." "Basso"
  exit 0
fi

ts=$(printf '%s' "$line" | sed -nE 's/^- ([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}) UTC.*/\1/p')
summary=$(printf '%s' "$line" | sed -E 's/^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC - //')

if [ -z "$ts" ]; then
  notify "KB nightly: unparseable record" "$line" "Basso"
  exit 0
fi

run_epoch=$(date -j -u -f '%Y-%m-%d %H:%M' "$ts" +%s 2>/dev/null || echo 0)
now_epoch=$(date -u +%s)
age_h=$(( (now_epoch - run_epoch) / 3600 ))

if [ "$run_epoch" -gt 0 ] && [ "$age_h" -le "$MAX_AGE_HOURS" ]; then
  notify "KB nightly OK (${age_h}h ago)" "$summary" "Glass"
else
  extra=""
  pgrep -xq Obsidian || extra=" NOTE: Obsidian is not running, so a record pushed by the nightly's headless copy may not have been pulled here yet - open Obsidian and re-check; if it still doesn't appear, check ~/kb-logs/."
  notify "KB nightly MISSING" "Newest record is ${age_h}h old: ${summary}.${extra}" "Basso"
fi

exit 0

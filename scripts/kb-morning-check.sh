#!/usr/bin/env bash
#
# Morning check for the nightly KB run - Mac side.
#
# The nightly runner (currently this Mac, via the com.benfried.kb-nightly
# launchd agent against the headless vault copy at ~/vault) appends one line
# per run to wikis/kb/log.md under "## Run history". A run that fails also
# leaves a line, containing "RUN FAILED". Obsidian Sync carries the line to
# every device.
#
# This script, fired by a launchd agent each morning, reads the newest line
# from both vault copies on this Mac (the app-managed one and the nightly's
# headless one) and decides:
#   OK      - newest record is fresh (default: under 30h) and not a failure
#   FAILED  - newest record says RUN FAILED
#   MISSING - no fresh record at all (runner never ran, or never pushed)
# OK raises a macOS notification. FAILED and MISSING also send an email,
# because banners vanish unseen (that hid a 13-night outage in Sep/Oct 2026).
# Every check appends one line to its own log.
#
# Email goes out through the Postfix relay on mulder.local (LAN, port 25,
# no login; it relays to Gmail). Recipient kept out of this public repo:
#   ~/.config/kb-nightly/alert.conf    KB_ALERT_TO=you@example.com
#                                      KB_ALERT_FROM=kb-nightly@your-domain
# mulder's STARTTLS is currently broken, so --ssl falls back to plain SMTP
# on the local network.

set -u

LOGS="${KB_VAULT_LOGS:-$HOME/kb/kb/wikis/kb/log.md $HOME/vault/wikis/kb/log.md}"
MAX_AGE_HOURS="${KB_MAX_AGE_HOURS:-30}"
CHECK_LOG="${KB_CHECK_LOG:-$HOME/Library/Logs/kb-morning-check.log}"
CONF="$HOME/.config/kb-nightly/alert.conf"
SMTP_URL="${KB_ALERT_SMTP_URL:-smtp://mulder.local:25}"

KB_ALERT_FROM=""; KB_ALERT_TO=""
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"
[ -n "$KB_ALERT_FROM" ] || KB_ALERT_FROM="kb-nightly@$(hostname -s).local"

mkdir -p "$(dirname "$CHECK_LOG")"
log() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*" >> "$CHECK_LOG"; }

notify() { # title, body, sound
  /usr/bin/osascript - "$1" "$2" "$3" <<'AS' >/dev/null 2>&1
on run argv
  display notification (item 2 of argv) with title (item 1 of argv) sound name (item 3 of argv)
end run
AS
}

send_email() { # subject, body; returns non-zero on failure
  if [ -z "$KB_ALERT_TO" ]; then log "EMAIL SKIPPED: no KB_ALERT_TO in $CONF"; return 1; fi
  msg=$(mktemp -t kb-alert) || return 1
  {
    printf 'From: KB nightly <%s>\r\n' "$KB_ALERT_FROM"
    printf 'To: %s\r\n' "$KB_ALERT_TO"
    printf 'Subject: %s\r\n' "$1"
    printf 'Date: %s\r\n' "$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')"
    printf 'Message-ID: <kb-check.%s.%s@%s>\r\n' "$(date +%s)" "$$" "${KB_ALERT_FROM#*@}"
    printf 'Content-Type: text/plain; charset=utf-8\r\n\r\n'
    printf '%s\r\n' "$2"
  } > "$msg"
  # -4: mulder.local resolves to IPv6 first, where Postfix isn't listening.
  err=$(/usr/bin/curl -4 -sS --max-time 60 --ssl --url "$SMTP_URL" \
        --mail-from "$KB_ALERT_FROM" \
        --mail-rcpt "$KB_ALERT_TO" --upload-file "$msg" 2>&1)
  rc=$?
  rm -f "$msg"
  if [ "$rc" -eq 0 ]; then log "EMAIL SENT to $KB_ALERT_TO"; else log "EMAIL FAILED (curl $rc): $err"; fi
  return "$rc"
}

alert() { # status, title, body
  log "$1: $3"
  if send_email "$2" "$3

Debug on the desktop Mac:
  tail -20 ~/kb-logs/launchd-kb-nightly.log
  launchctl print gui/\$(id -u)/com.benfried.kb-nightly
Re-run by hand:
  launchctl kickstart gui/\$(id -u)/com.benfried.kb-nightly"; then
    notify "$2" "$3" "Basso"
  else
    notify "$2 (EMAIL FAILED)" "$3 - see $CHECK_LOG" "Basso"
  fi
  exit 0
}

# Newest "- YYYY-MM-DD HH:MM UTC - ..." Run history line across both copies.
best_line=""; best_epoch=0; seen_file=0
for f in $LOGS; do
  [ -f "$f" ] || continue
  seen_file=1
  l=$(awk '/^## Run history/{f=1;next} f&&/^- [0-9]/{l=$0} END{print l}' "$f")
  t=$(printf '%s' "$l" | sed -nE 's/^- ([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}) UTC.*/\1/p')
  [ -n "$t" ] || continue
  e=$(date -j -u -f '%Y-%m-%d %H:%M' "$t" +%s 2>/dev/null || echo 0)
  if [ "$e" -gt "$best_epoch" ]; then best_epoch=$e; best_line=$l; fi
done

[ "$seen_file" -eq 1 ] || alert MISSING "KB nightly: vault log missing" "No log.md found at: $LOGS"
[ -n "$best_line" ] || alert MISSING "KB nightly: NO RUN RECORD" "log.md has no parseable Run history entries."

summary=$(printf '%s' "$best_line" | sed -E 's/^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC - //')
age_h=$(( ($(date -u +%s) - best_epoch) / 3600 ))

if [ "$age_h" -gt "$MAX_AGE_HOURS" ]; then
  alert MISSING "KB nightly MISSING" "Newest run record is ${age_h}h old (limit ${MAX_AGE_HOURS}h): ${summary}"
fi
case "$summary" in
  *"RUN FAILED"*) alert FAILED "KB nightly FAILED" "Last night's run failed ${age_h}h ago: ${summary}" ;;
esac

log "OK (${age_h}h ago): $summary"
notify "KB nightly OK (${age_h}h ago)" "$summary" "Glass"
exit 0

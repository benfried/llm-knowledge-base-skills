#!/usr/bin/env bash
#
# Nightly knowledge-base maintenance — desktop. Invoked by the
# com.benfried.kb-nightly launchd agent (02:07 local, DST-correct).
#
# This repo copy is the source of truth; launchd runs an installed copy:
#   install -m 755 scripts/kb-nightly.sh ~/bin/kb-nightly.sh
# Never point launchd at this file directly: the script git-pulls this repo
# at startup, and bash reads scripts incrementally, so a pull that changes
# this file would corrupt the running copy.
#
# Must stay /bin/bash 3.2-clean (launchd's bash); check with: /bin/bash -n
#
# NEVER paste the Claude token into this script. It lives only in
# ~/.config/kb-nightly/claude-oauth-token (mode 600) and this repo is public.

set -u
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

LOGDIR="$HOME/kb-logs"
mkdir -p "$LOGDIR"
find "$LOGDIR" -name 'kb-nightly-*.log' -mtime +30 -delete 2>/dev/null
LOG="$LOGDIR/kb-nightly-$(date -u +%F).log"

# Long-lived auth (claude setup-token, ~1 year). Without it, claude -p uses the
# interactive Keychain login, which expires and cannot be renewed unattended
# (that silently broke every run 2026-09-24..10-06). Renew before it lapses.
TOKEN_FILE="$HOME/.config/kb-nightly/claude-oauth-token"
if [ -r "$TOKEN_FILE" ]; then
  CLAUDE_CODE_OAUTH_TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
  export CLAUDE_CODE_OAUTH_TOKEN
fi

VAULT_LOG="$HOME/vault/wikis/kb/log.md"
OUT=$(mktemp -t kb-nightly) || OUT="$LOGDIR/.kb-nightly-out"

# read -d '' instead of PROMPT=$(cat <<EOP): /bin/bash 3.2 (what launchd
# invokes) can't parse a heredoc containing an apostrophe inside $(...).
read -r -d '' PROMPT <<'EOP' || true
Run the nightly knowledge-base maintenance loops against the Obsidian Sync vault bound at ~/vault. Both skills live in this repo under .claude/skills/.

1. Invoke the `enrich-notes-loop-cloud` skill and follow its instructions exactly. It runs `ob sync` to pull the vault at ~/vault, enriches every note that lacks a done-stamp (`enrichedAt` in YAML frontmatter, or `#+enriched_at:` for org-mode notes) with topic tags, source attribution and Related links, expands any link-only bookmark into a full web clipping via clip-link first, then runs `ob sync` again to push results back.

2. Then invoke the `refresh-wiki-cloud` skill and follow its instructions exactly. It syncs, updates every wiki under ~/vault/wikis/ by ingesting newly enriched notes as sources and updating concept/people/org pages, index counts and log.md, then syncs back.

3. ALWAYS leave a run record, even when there was nothing to do. Append one line to ~/vault/wikis/kb/log.md under a `## Run history` heading (create that heading at the end of the file if it does not exist yet), in exactly this format:

   - YYYY-MM-DD HH:MM UTC - N notes enriched, M bookmarks clipped, P wiki pages changed[, note]

   Use the real UTC date and time from `date -u`. Say `0 notes enriched, 0 bookmarks clipped, 0 wiki pages changed` when it was a no-op - a quiet night must still leave a line. Add a short trailing note only if something was skipped or went wrong. Then run `cd ~/vault && ob sync` one final time so the record is pushed. This line is the only evidence visible from other devices that the run happened at all, so never omit it.

Hard constraints:
- Never delete notes, attachments, or wiki pages.
- Raw notes outside wikis/ are immutable sources - only add frontmatter and a Related section during enrichment; never rewrite their content.
- Reuse existing tags from the vault's tags.md registry; be reluctant to coin new ones, and register any new tag there with a one-line description.
- Link only to notes that actually exist; never invent a wikilink target.
- If `ob sync` reports a conflict, or you hit an authentication or setup error at any point, STOP immediately and report it rather than making further edits. In that case you will not be able to write the run record - report the error instead.
- If a page fetch fails or is paywalled, leave the bookmark exactly as it was and report the URL. A broken half-clipping is worse than a bookmark.

Finish with a short report: how many notes were enriched, which bookmarks were clipped, which wiki pages changed, anything deliberately skipped and why, and any follow-up questions for the user.
EOP

{
  echo "=== kb-nightly start $(date -u +%FT%TZ) ==="
  cd "$HOME/src/llm-knowledge-base-skills" || { echo "FATAL: repo missing"; exit 1; }
  git pull --ff-only 2>&1 || echo "WARN: git pull failed - continuing with existing checkout"
  # Fail fast with a clear reason when auth is broken, before any vault edits.
  if ! claude -p "Reply with the single word ready." --model claude-sonnet-5 >"$OUT" 2>&1; then
    rc=1
    echo "AUTH PREFLIGHT FAILED: $(tail -1 "$OUT")"
  else
    claude -p "$PROMPT" --permission-mode bypassPermissions --model claude-sonnet-5 2>&1 | tee "$OUT"
    rc=${PIPESTATUS[0]}
  fi
  if [ "$rc" -ne 0 ]; then
    # Leave a visible failure record in the vault so other devices and the
    # morning check see it. Skipped if the run reported an ob sync conflict:
    # pushing more edits then could make the conflict worse.
    reason=$(grep -v '^[[:space:]]*$' "$OUT" | tail -1 | tr -d '\r' | cut -c1-200)
    [ -n "$reason" ] || reason="claude exited $rc with no output"
    if grep -qi 'conflicted file' "$OUT"; then
      echo "Not writing a failure record: run output mentions a sync conflict."
    elif [ -f "$VAULT_LOG" ]; then
      (cd "$HOME/vault" && ob sync 2>&1) || echo "WARN: ob sync pull before failure record failed"
      echo "- $(date -u '+%Y-%m-%d %H:%M') UTC - RUN FAILED (exit $rc): $reason - see ~/kb-logs/ on the desktop Mac" >> "$VAULT_LOG"
      (cd "$HOME/vault" && ob sync 2>&1) || echo "WARN: ob sync of failure record failed"
    fi
  fi
  rm -f "$OUT"
  echo "=== kb-nightly exit $rc $(date -u +%FT%TZ) ==="
  exit "$rc"
} 2>&1 | tee -a "$LOG"
exit "${PIPESTATUS[0]}"

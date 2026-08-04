#!/usr/bin/env bash
#
# SessionStart hook for scheduled cloud routines (see docs/cloud-automation.md,
# Option B). Wired up in .claude/settings.json.
#
# Materializes credentials from environment variables and binds the Obsidian
# Sync vault at ~/vault, so the -cloud skills can run `ob sync` against it.
#
# This runs on every session start rather than in the environment setup script,
# because setup output is snapshotted and reused: a credential baked into the
# snapshot goes stale the moment you rotate it. Doing it here means rotation
# takes effect on the next run.
#
# The script never fails the session. Every step is guarded and it always exits
# 0 — a missing cookie jar or password degrades gracefully instead of aborting
# a night's run.
#
# Environment variables (set on the cloud environment, not in this repo):
#   OBSIDIAN_AUTH_TOKEN            required - headless CLI auth token
#   OBSIDIAN_ENCRYPTION_PASSWORD   required if the vault uses end-to-end encryption
#   CLIP_LINK_COOKIES_B64          optional - base64 of the clip-link cookie jar
#   OBSIDIAN_VAULT_NAME            optional - remote vault name (default: kb)
#   OBSIDIAN_DEVICE_NAME           optional - shows in sync version history

set -u

VAULT_PATH="$HOME/vault"
VAULT_NAME="${OBSIDIAN_VAULT_NAME:-kb}"
DEVICE_NAME="${OBSIDIAN_DEVICE_NAME:-claude-routine}"

log() { printf '[cloud-session-start] %s\n' "$1"; }

# Pull the line that actually says what went wrong out of a command's output.
#
# `ob` is a Node CLI: on failure it prints the real message first and then a
# stack trace. Logging the TAIL of that gives you "at z ... at Command.<anonymous>"
# and hides the cause — which is exactly what happened on the first live run,
# where a 403 was reported as unreadable stack frames. Prefer the first line
# that looks like an error; fall back to the first non-empty line.
first_error() {
  printf '%s\n' "$1" | grep -m1 -iE 'error|forbidden|denied|unauthor|invalid|not found|[0-9]{3}' \
    || printf '%s\n' "$1" | grep -m1 -v '^[[:space:]]*$' \
    || printf 'no output'
}

# --- 1. Obsidian headless auth token ----------------------------------------

if [ -n "${OBSIDIAN_AUTH_TOKEN:-}" ]; then
  # Two facts about `ob`'s token resolution, both read from cli.js source
  # (neither is in the README or help.obsidian.md):
  #   1. It checks the OBSIDIAN_AUTH_TOKEN env var BEFORE any file — so in an
  #      environment that sets the var, these files are belt-and-braces.
  #   2. The file path is platform-dependent: macOS uses ~/.obsidian-headless,
  #      Linux uses XDG (~/.config/obsidian-headless). Write both; a wrong
  #      single choice here cost a debugging cycle on the Linux sandbox.
  for _obdir in "$HOME/.obsidian-headless" "${XDG_CONFIG_HOME:-$HOME/.config}/obsidian-headless"; do
    mkdir -p "$_obdir"
    printf '%s' "$OBSIDIAN_AUTH_TOKEN" > "$_obdir/auth_token"
    chmod 600 "$_obdir/auth_token"
  done
  # Length and a hash prefix — never the value itself.
  #
  # Length alone is not enough: the auth token is 32 lowercase hex characters,
  # which is the same shape as an Obsidian vault ID. Copying the vault ID into
  # this variable produces a 32-char value that passes every superficial check
  # and then 403s. The fingerprint is a SHA-256 prefix, so it is safe to paste
  # into a chat or ticket, and comparing it against the fingerprint of
  # ~/.obsidian-headless/auth_token on a working machine settles in one glance
  # whether the right secret is loaded.
  fp=$(printf '%s' "$OBSIDIAN_AUTH_TOKEN" | sha256sum 2>/dev/null | cut -c1-12) \
    || fp=$(printf '%s' "$OBSIDIAN_AUTH_TOKEN" | shasum -a 256 | cut -c1-12)
  log "auth token written (${#OBSIDIAN_AUTH_TOKEN} chars, fingerprint ${fp:-unavailable})"
else
  # No env var — but that is only a problem when there are no stored
  # credentials either. On a persistent host (a VM where `ob login` ran once),
  # the token lives in a file and the env var is legitimately absent. A prior
  # version of this hook unconditionally logged "vault sync cannot run" here;
  # a nightly agent believed it, treated it as an authentication failure, and
  # stopped without ever trying `ob`. Only raise the alarm when it is true.
  if [ -s "$HOME/.obsidian-headless/auth_token" ] || [ -s "${XDG_CONFIG_HOME:-$HOME/.config}/obsidian-headless/auth_token" ]; then
    log "using stored ob credentials (no OBSIDIAN_AUTH_TOKEN env var; token file present)"
  else
    log "no Obsidian credentials: OBSIDIAN_AUTH_TOKEN unset and no stored auth_token file - vault sync cannot run"
  fi
fi

# --- 2. clip-link cookie jar (optional) -------------------------------------
#
# Absence is fine: clip-link still clips public pages, and leaves paywalled
# bookmarks untouched rather than writing a half-clipping.

if [ -n "${CLIP_LINK_COOKIES_B64:-}" ]; then
  mkdir -p "$HOME/.config/clip-link"
  if printf '%s' "$CLIP_LINK_COOKIES_B64" | base64 -d > "$HOME/.config/clip-link/cookies.txt" 2>/dev/null; then
    chmod 600 "$HOME/.config/clip-link/cookies.txt"
    log "cookie jar written"
  else
    rm -f "$HOME/.config/clip-link/cookies.txt"
    log "CLIP_LINK_COOKIES_B64 did not base64-decode - continuing without a jar"
  fi
elif [ -s "$HOME/.config/clip-link/cookies.txt" ]; then
  log "using existing cookie jar at ~/.config/clip-link/cookies.txt"
else
  log "no cookie jar - paywalled bookmarks will be left as bookmarks"
fi

# --- 3. Bind the vault ------------------------------------------------------
#
# --path is ALWAYS pinned, deliberately.
#
# `ob sync-setup` binds the CURRENT WORKING DIRECTORY when --path is omitted.
# Run it from the wrong folder once and it will bind that folder to your notes
# vault and start uploading its contents. That has happened; it is why this
# comment exists. Do not remove the flag, and do not rely on cwd here.

if ! command -v ob >/dev/null 2>&1; then
  log "ob not found - the environment setup script should 'npm install -g obsidian-headless'"
  exit 0
fi

# Idempotent: the binding survives on persistent hosts and inside a session,
# and re-running sync-setup over an existing bind is pointless noise. Check
# BEFORE the credential gate: an already-bound vault (a VM set up with an
# interactive `ob login`) needs no env var at all, and this hook must say so
# plainly rather than exiting in silence.
if ob sync-list-local --json 2>/dev/null | grep -qF "\"$VAULT_PATH\""; then
  log "vault already bound at $VAULT_PATH - ready to sync"
  exit 0
fi

# From here on we would be BINDING a vault for the first time, which does need
# a credential from somewhere: the env var, or a stored token file.
if [ -z "${OBSIDIAN_AUTH_TOKEN:-}" ] \
   && [ ! -s "$HOME/.obsidian-headless/auth_token" ] \
   && [ ! -s "${XDG_CONFIG_HOME:-$HOME/.config}/obsidian-headless/auth_token" ]; then
  exit 0
fi

mkdir -p "$VAULT_PATH"

# Preflight: does this token actually authenticate, and can it see the vault we
# are about to bind? Distinguishes "credential is wrong" from "sync-setup call
# is wrong" — two failures that otherwise look identical in the logs.
probe=$(ob sync-list-remote --json 2>&1); probe_rc=$?
if [ "$probe_rc" -ne 0 ]; then
  log "auth token REJECTED by the sync API: $(first_error "$probe")"
  log "  -> re-copy OBSIDIAN_AUTH_TOKEN from ~/.obsidian-headless/auth_token on a machine where 'ob sync-list-remote' works"
  exit 0
fi

visible=$(printf '%s' "$probe" | tr ',' '\n' | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | tr '\n' ' ')
log "auth token accepted; vaults visible: ${visible:-<none>}"
if [ -n "$visible" ] && ! printf '%s ' $visible | grep -qF "$VAULT_NAME "; then
  log "WARNING: '$VAULT_NAME' is not among the visible vaults - check OBSIDIAN_VAULT_NAME"
fi

if [ -n "${OBSIDIAN_ENCRYPTION_PASSWORD:-}" ]; then
  out=$(ob sync-setup --vault "$VAULT_NAME" --path "$VAULT_PATH" \
          --password "$OBSIDIAN_ENCRYPTION_PASSWORD" \
          --device-name "$DEVICE_NAME" 2>&1); rc=$?
  # Redact before anything reaches a log the operator might paste around.
  out=${out//"$OBSIDIAN_ENCRYPTION_PASSWORD"/[redacted]}
else
  out=$(ob sync-setup --vault "$VAULT_NAME" --path "$VAULT_PATH" \
          --device-name "$DEVICE_NAME" 2>&1); rc=$?
fi

if [ "$rc" -eq 0 ]; then
  log "bound vault '$VAULT_NAME' at $VAULT_PATH"
else
  log "sync-setup failed (exit $rc): $(first_error "$out")"
  if printf '%s' "$out" | grep -qi 'password'; then
    log "  -> looks password-related; check OBSIDIAN_ENCRYPTION_PASSWORD"
  fi
fi

exit 0

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

# --- 1. Obsidian headless auth token ----------------------------------------

if [ -n "${OBSIDIAN_AUTH_TOKEN:-}" ]; then
  mkdir -p "$HOME/.obsidian-headless"
  printf '%s' "$OBSIDIAN_AUTH_TOKEN" > "$HOME/.obsidian-headless/auth_token"
  chmod 600 "$HOME/.obsidian-headless/auth_token"
  log "auth token written"
else
  log "OBSIDIAN_AUTH_TOKEN is unset - vault sync cannot run"
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

if [ -z "${OBSIDIAN_AUTH_TOKEN:-}" ]; then
  exit 0
fi

mkdir -p "$VAULT_PATH"

# Idempotent: the binding survives inside a session, and re-running sync-setup
# over an existing bind is pointless noise.
if ob sync-list-local --json 2>/dev/null | grep -qF "\"$VAULT_PATH\""; then
  log "vault already bound at $VAULT_PATH"
  exit 0
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
  log "sync-setup failed (exit $rc): $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
fi

exit 0

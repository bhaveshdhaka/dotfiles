#!/usr/bin/env bash
# shellcheck disable=SC2329 # step_* functions are invoked indirectly via run_step "$@"
#
# update-all-jp.sh — unattended update orchestrator for the Japan VPS
# ===================================================================
# Host:     root@142.91.108.254 (never sleeps, no launchd → cron)
# User:     root (no sudoers needed — the scoped sudoers is a Mac-only concept)
# Cadence:  Sunday 03:00 server-local time, via cron (see the cron line below).
#
# Same design as the Mac's update-all.sh, trimmed to what Japan runs:
#   1. pi update --all          pi + its extensions
#   2. fm-update.sh             firstmate self-update, fast-forward only
#   3. herdr update             herdr's native channel updater (0.8.0 stable)
# Optional (commented): system packages via apt and npm globals.
#
# Failure policy: identical to the Mac — each step runs independently, a
# failure is logged with the step name and the run continues; the script
# exits non-zero if ANY step failed.
#
# Deployment (docs only — do NOT deploy from this repo; the captain copies
# it to the server manually when he decides to):
#   scp update-all-jp.sh root@142.91.108.254:/root/
#   chmod +x /root/update-all-jp.sh
#
# Cron line (root's crontab — `crontab -e`):
#   0 3 * * 0 /root/update-all-jp.sh
# The script writes its own timestamped logs to /var/log/auto-update-jp/ and
# keeps the newest 30; cron output (if any) also lands in the cron mail/log.
#
# Verify with:
#   crontab -l | grep update-all-jp
#   ls -lt /var/log/auto-update-jp/ | head
#
# NOTE: paths below are best-effort assumptions (pi/herdr on PATH, firstmate
# at /root/firstmate). Verify each `command -v` on the server before the first
# run and adjust the variables at the top of this file if needed.
set -euo pipefail

# --- config (verify on the server) ----------------------------------------
FM_UPDATE="${FM_UPDATE:-/root/firstmate/bin/fm-update.sh}"
HERDR_CMD="${HERDR_CMD:-herdr}"
PI_CMD="${PI_CMD:-pi}"
LOG_DIR="${AUTO_UPDATE_LOG_DIR:-/var/log/auto-update-jp}"
KEEP_LOGS="${AUTO_UPDATE_KEEP_LOGS:-30}"

FAILED_STEPS=""

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

preflight() {
  log "==> Preflight"
  local missing=""
  for c in "$PI_CMD" "$HERDR_CMD"; do
    command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
  done
  [ -x "$FM_UPDATE" ] || missing="$missing $FM_UPDATE(not executable)"
  if [ -n "$missing" ]; then
    log "ERROR: missing on this server:$missing — adjust the config block at the top"
    return 1
  fi
  log "Preflight OK — pi, herdr, firstmate all present"
  return 0
}

run_step() {
  local name="$1"
  local desc="$2"
  shift 2
  log "===== Step: $name — $desc"
  if "$@"; then
    log "----- Step: $name — OK"
  else
    local rc=$?
    log "----- Step: $name — FAILED (exit $rc)"
    FAILED_STEPS="$FAILED_STEPS $name"
  fi
}

step_pi() {
  log "pi update --all (pi + extensions)"
  "$PI_CMD" update --all
}

step_firstmate() {
  log "$FM_UPDATE (fast-forward only; 'already current' is success)"
  "$FM_UPDATE"
}

step_herdr() {
  log "$HERDR_CMD update (herdr channel updater)"
  "$HERDR_CMD" update
}

# --- optional steps (uncomment if the server has them) ---------------------
# step_apt() {
#   log "apt-get update && apt-get upgrade -y (system packages)"
#   apt-get update
#   DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
# }
#
# step_npm() {
#   log "npm update -g (globals)"
#   npm update -g
# }

main() {
  mkdir -p "$LOG_DIR"
  exec > >(tee -a "$LOG_DIR/update-$(date +%Y%m%d-%H%M%S).log") 2>&1

  log "===== auto-update (Japan) start"
  log "host: $(hostname)  user: $(id -un)"

  if ! preflight; then
    log "===== auto-update (Japan) ABORTED (preflight failed)"
    exit 1
  fi

  run_step "pi" "pi update --all" step_pi
  run_step "firstmate" "fm-update.sh (fast-forward only)" step_firstmate
  run_step "herdr" "herdr update" step_herdr
  # run_step "apt" "apt-get update && upgrade" step_apt
  # run_step "npm" "npm update -g" step_npm

  # Keep only the newest KEEP_LOGS logs.
  find "$LOG_DIR" -maxdepth 1 -type f -name 'update-*.log' -print \
    | sort -r \
    | tail -n +$((KEEP_LOGS + 1)) \
    | while IFS= read -r old; do rm -f -- "$old"; done || true

  if [ -n "$FAILED_STEPS" ]; then
    log "===== auto-update (Japan) FINISHED WITH FAILURES:$FAILED_STEPS"
    exit 1
  fi
  log "===== auto-update (Japan) finished OK"
  exit 0
}

main "$@"

#!/usr/bin/env bash
# shellcheck disable=SC2329 # step_* functions are invoked indirectly via run_step "$@"
#
# update-all.sh — unattended Mac update orchestrator
# ===================================================
# Runs every Sunday 03:00 via launchd (com.bhavesh.auto-update), or manually:
#
#   ./update-all.sh
#
# Holds the Mac awake for the whole run (caffeinate -dimsu), logs to
# ~/Library/Logs/com.bhavesh.auto-update/update-<timestamp>.log, and never
# prompts for a password (requires the scoped sudoers file — see
# sudoers/fm-update.sudoers and the README "Automatic updates" section).
#
# Steps, in order (each is logged with its name):
#   1. brew update && brew upgrade     formulae + casks; pkg casks use
#                                      /usr/sbin/installer via the scoped sudoers
#   2. nix flake update + ./rebuild.sh nix-darwin switch via darwin-rebuild
#                                      (NOPASSWD in the scoped sudoers)
#   3. pi update --all                 pi + its extensions (pinned packages stay
#                                      pinned by design — see registry.md)
#   4. npm update -g                   AXI/npm tools under /opt/homebrew
#   5. $HOME/firstmate/bin/fm-update.sh firstmate self-update, fast-forward only
#
# Failure policy (documented in the README):
#   Every step runs independently. A failed step is logged with its name and
#   the run CONTINUES with the next step, so one broken layer (e.g. the vlc
#   cask on Homebrew 6.0.1's missing command_wrapper DSL) never blocks the
#   other layers. The script exits NON-ZERO if any step failed, so a failed
#   Sunday run is visible in the log and to launchd.
#
# Invariants:
#   - bash 3.2 (macOS /bin/bash) compatible — no bash 4+ features.
#   - shellcheck-clean.
#   - Never prompts: the scoped NOPASSWD sudoers must be installed
#     (/etc/sudoers.d/fm-update). The preflight below aborts the run with a
#     clear message instead of ever hanging on a password prompt.
set -euo pipefail
# brew update runs explicitly in step 1; suppress brew's implicit auto-update
# inside every other brew invocation (including nix-homebrew's during rebuild).
export HOMEBREW_NO_AUTO_UPDATE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$SCRIPT_DIR"                                  # this repo (== ~/.dotfiles when installed)
LOG_DIR="${AUTO_UPDATE_LOG_DIR:-$HOME/Library/Logs/com.bhavesh.auto-update}"
LOG_FILE="$LOG_DIR/update-$(date +%Y%m%d-%H%M%S).log"
KEEP_LOGS="${AUTO_UPDATE_KEEP_LOGS:-30}"
SUDOERS_FILE="/etc/sudoers.d/fm-update"

# The only two commands the scoped sudoers grants NOPASSWD for — preflight
# verifies both are effective before anything runs.
SUDOERS_CMDS=(/run/current-system/sw/bin/darwin-rebuild /usr/sbin/installer)

FAILED_STEPS=""

usage() {
  cat <<'EOF'
update-all.sh — unattended Mac update orchestrator

Usage: ./update-all.sh [--help]

Runs, in order: brew update+upgrade, nix flake update+rebuild.sh,
pi update --all, npm update -g, firstmate bin/fm-update.sh.
Holds the Mac awake (caffeinate -dimsu), logs to
~/Library/Logs/com.bhavesh.auto-update/update-<timestamp>.log, never prompts
(requires the scoped sudoers — see README "Automatic updates"), and exits
non-zero if any step failed.

Env overrides:
  AUTO_UPDATE_LOG_DIR                 log directory (default above)
  AUTO_UPDATE_KEEP_LOGS               how many logs to keep (default 30)
  AUTO_UPDATE_SKIP_SUDOERS_CHECK=1    skip the scoped-sudoers preflight
                                      (manual testing only)
EOF
}

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

rotate_logs() {
  # Keep only the newest KEEP_LOGS logs. Names are script-generated
  # (update-YYYYmmdd-HHMMSS.log) so plain sort is correct and safe here.
  find "$LOG_DIR" -maxdepth 1 -type f -name 'update-*.log' -print \
    | sort -r \
    | tail -n +$((KEEP_LOGS + 1)) \
    | while IFS= read -r old; do rm -f -- "$old"; done || true
}

preflight() {
  log "==> Preflight"
  local missing=""
  local c=""
  for c in brew nix pi npm git; do
    command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
  done
  if [ -n "$missing" ]; then
    log "ERROR: tools missing from PATH:$missing (launchd PATH is set in the plist)"
    return 1
  fi

  if [ "${AUTO_UPDATE_SKIP_SUDOERS_CHECK:-0}" = "1" ]; then
    log "WARNING: AUTO_UPDATE_SKIP_SUDOERS_CHECK=1 — scoped-sudoers check skipped (testing only)"
    return 0
  fi

  if [ ! -f "$SUDOERS_FILE" ]; then
    log "ERROR: $SUDOERS_FILE is not installed."
    log "       Install it once, manually (captain):"
    log "         sudo install -m 0440 -o root -g wheel sudoers/fm-update.sudoers $SUDOERS_FILE"
    log "       See README 'Automatic updates' — the scope is deliberately narrow"
    log "       (darwin-rebuild + /usr/sbin/installer, nothing else)."
    return 1
  fi

  local mode=""
  mode="$(stat -f %Lp "$SUDOERS_FILE" 2>/dev/null || echo bad)"
  if [ "$mode" != "440" ]; then
    log "ERROR: $SUDOERS_FILE must be mode 0440 (currently $mode)."
    log "       Fix: sudo chmod 0440 $SUDOERS_FILE"
    return 1
  fi

  local cmd=""
  for cmd in "${SUDOERS_CMDS[@]}"; do
    if ! sudo -n -l "$cmd" 2>&1 | grep -q NOPASSWD; then
      log "ERROR: 'sudo -n -l $cmd' shows no NOPASSWD rule — the scoped sudoers is not effective."
      log "       Repair $SUDOERS_FILE (see README) so the run can never prompt."
      return 1
    fi
  done
  log "Preflight OK — scoped NOPASSWD effective for: ${SUDOERS_CMDS[*]}"
  return 0
}

# --- steps -----------------------------------------------------------------

step_brew() {
  log "brew update"
  brew update
  log "brew upgrade (formulae + casks; pkg casks run /usr/sbin/installer via scoped sudoers)"
  brew upgrade
}

step_nix() {
  cd "$REPO_DIR"
  log "nix flake update (rewrites flake.lock in the working tree — captain commits it later)"
  nix flake update
  log "rebuild.sh — darwin-rebuild switch (sudo via scoped NOPASSWD)"
  ./rebuild.sh
}

step_pi() {
  log "pi update --all (pi + extensions; the two pinned packages stay pinned by design)"
  pi update --all
}

step_npm() {
  log "npm update -g (AXI/npm tools under /opt/homebrew/lib/node_modules)"
  npm update -g
}

step_firstmate() {
  local fm_update="$HOME/firstmate/bin/fm-update.sh"
  if [ ! -x "$fm_update" ]; then
    log "firstmate update script not found at $fm_update"
    return 1
  fi
  log "$fm_update (fast-forward only; 'already current' is success)"
  "$fm_update"
}

# --- one-time setup: Microsoft AutoUpdate (MAU) OFF ------------------------
# Microsoft apps stop silently self-updating and manual/Homebrew installs own
# them. This is a ONE-TIME manual change (documented in the README section
# "Microsoft apps stop self-updating"), applied by the captain after review —
# it is deliberately NOT part of the weekly run by default.
#
#   defaults write com.microsoft.autoupdate2 HowToCheck -string "Manual"
#   defaults read com.microsoft.autoupdate2 HowToCheck     # → Manual
#
# The key was verified against the installed MAU preferences (was
# "AutomaticCheck" before). Optional, stronger: also disable MAU's background
# system agent so no MAU daemon runs at all:
#
#   sudo launchctl disable system/com.microsoft.update.agent
#
# Re-enable automatic checks later:
#   defaults write com.microsoft.autoupdate2 HowToCheck -string "AutomaticCheck"
#
# If you prefer the orchestrator to OWN the setting (idempotent, applied on
# every run), uncomment this step and add it to main():
#
# run_step "mau" "HowToCheck=Manual (Microsoft AutoUpdate off)" step_mau
#
# step_mau() {
#   if [ "$(defaults read com.microsoft.autoupdate2 HowToCheck 2>/dev/null || echo missing)" != "Manual" ]; then
#     log "MAU: setting HowToCheck=Manual"
#     defaults write com.microsoft.autoupdate2 HowToCheck -string "Manual"
#   else
#     log "MAU: HowToCheck already Manual"
#   fi
# }

# --- runner ----------------------------------------------------------------

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

main() {
  mkdir -p "$LOG_DIR"
  # Everything from here on goes to the timestamped log AND to stdout/stderr
  # (launchd also captures the latter).
  exec > >(tee -a "$LOG_FILE") 2>&1

  log "===== auto-update start"
  log "log file: $LOG_FILE"
  log "repo:     $REPO_DIR"
  log "user:     $(id -un)  host: $(hostname -s)"

  # Hold the Mac awake for the whole run. -s (prevent system sleep) is part of
  # the approved design; if a future macOS version refuses it without root,
  # caffeinate prints a warning and the remaining assertions (-dimu) still hold.
  caffeinate -dimsu -w $$ &
  log "caffeinate -dimsu holding the Mac awake during the run (pid $!)"

  if ! preflight; then
    log "===== auto-update ABORTED (preflight failed) — fix per the messages above and re-run"
    exit 1
  fi

  run_step "brew" "brew update && brew upgrade" step_brew
  run_step "nix" "nix flake update + rebuild.sh" step_nix
  run_step "pi" "pi update --all" step_pi
  run_step "npm" "npm update -g" step_npm
  run_step "firstmate" "bin/fm-update.sh (fast-forward only)" step_firstmate

  rotate_logs
  if [ -n "$FAILED_STEPS" ]; then
    log "===== auto-update FINISHED WITH FAILURES:$FAILED_STEPS"
    log "review $LOG_FILE"
    exit 1
  fi
  log "===== auto-update finished OK"
  exit 0
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

main "$@"

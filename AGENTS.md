# Project notes for agents

Deliberate decisions in this repo - do NOT silently revert them:

- `homebrew.onActivation.cleanup = "uninstall"` in `configuration.nix` is intentional and permanent (captain decision 2026-08-15). Combined with `onActivation.extraFlags = [ "--force" ]`, every switch uninstalls any Homebrew formula or cask not declared in `brews`/`casks`, forcing the good habit of declaring everything in Nix instead of installing ad-hoc, which keeps the machine reproducible. Do not change it to `zap` or `none`. Users are warned about its effect in README.md; this note is for anyone tempted to change the setting itself.
- Never commit `.no-mistakes/` validation evidence to this public repo. `.no-mistakes/` is gitignored; if a validation pipeline stages evidence into a branch, drop it before merging.
- The weekly auto-update pipeline is `update-all.sh` (launchd, Sunday 03:00, `com.bhavesh.auto-update.plist`), with `sudoers/fm-update.sudoers` as the deliberately narrow NOPASSWD scope and `registry.md` as the single "what's installed / how it updates" manifest. `update-all-jp.sh` is the Japan VPS (cron) variant. See the README "Automatic updates" section; never broaden the sudoers scope.
- `Brewfile` at the repo root is a non-enforcing capture landing (recorded 2026-08-17 from the firstmate repo root after a capture-workflow miss): nothing in this repo runs `brew bundle` automatically, and `configuration.nix`'s `brews`/`casks` arrays remain the enforcing source of truth. Do not prune or extend its 21 lines to reconcile with the nix config (vlc et al. in its comments are not in the file by design); the file's own header documents its role.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.

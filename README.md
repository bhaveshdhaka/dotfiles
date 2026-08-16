# dotfiles

Watch the walkthrough: https://youtu.be/5N-okeDdIuI

My personal Mac setup, managed with nix-darwin and home-manager.
One repo, one command, and a fresh Mac ends up configured the same way every time.

## Contributing / Using This Repo

These are my personal dotfiles, shared publicly so people can read them, learn from them, and fork them freely.
Feature requests and pull requests are not accepted here, and PRs are auto-closed.
If you find a bug, please open a GitHub Issue using the bug report template.

## What you get

Running the switch builds:

- System settings (dark mode, key repeat, dock, Finder, trackpad)
- Homebrew apps (casks and CLI tools)
- Nix user packages (ripgrep, fd, fzf, jq, lazygit, Neovim, Hack Nerd Font)
- Shell (zsh, aliases, starship prompt)
- Editor (Neovim config with the rose-pine moon theme)
- Terminal (WezTerm config with the rose-pine moon theme and dimmed unfocused windows)
- Agent configs (Claude, Codex, opencode all share one AGENTS.md)
- Optional Pi theme and local extensions, generic UI settings and model overrides, plus two deliberately pinned third-party Pi packages

## Prerequisites

- Apple Silicon Mac, by default.
- Intel Mac: change one line.
  In `configuration.nix`, set `nixpkgs.hostPlatform = "x86_64-darwin";` (the comment right there tells you the same thing).

## Fresh-machine setup

On a brand new Mac, from a bare clone of this repo:

```sh
git clone https://github.com/kunchenguid/dotfiles.git
cd dotfiles
```

Before you run it: review "Make it yours" below.
Change the host label or CPU architecture if needed, and read the Homebrew cleanup warning.
`bootstrap.sh` applies the config to your machine, so do this first.

```sh
./bootstrap.sh
```

`bootstrap.sh` does four things, in order:

1. Installs Determinate Nix, if it isn't already installed.
2. Symlinks this repo to `~/.dotfiles`.
   This has to happen before the first build, because `home.nix` points at config files through `~/.dotfiles`.
3. Checks the `user` configured in `flake.nix` against your actual macOS username, and offers to fix it for you if they differ.
4. Runs the first `darwin-rebuild switch`.
   It fetches the `darwin-rebuild` tool from the nix-darwin 26.05 release branch, then applies this repo's locked flake config.

After that, `darwin-rebuild` exists and you're on the normal workflow below.

### Validate without applying

Once Nix is installed (`bootstrap.sh` step 1 handles that), you can check that the config builds without touching your system - handy when you have edited something:

```sh
nix flake check --no-build
nix build .#darwinConfigurations.mac.system --dry-run
```

If you renamed the host label in "Make it yours", substitute your label for `mac` in these commands.

## Daily use

Edit the config files in place, then apply:

```sh
./rebuild.sh
```

That's it.
No separate build-and-copy step.

## Automatic updates

This machine updates itself, unattended, every **Sunday 03:00**: `launchd` fires
the `com.bhavesh.auto-update` LaunchAgent (`com.bhavesh.auto-update.plist`),
which runs `update-all.sh` — one orchestrator that holds the Mac awake
(`caffeinate -dimsu`), runs each update layer in order, logs everything, and
never prompts for a password.

Steps, in order:

1. `brew update && brew upgrade` (formulae + casks)
2. `git pull --ff-only`, then `nix flake update` + `./rebuild.sh` (nix-darwin switch)
3. `pi update --all` (pi + its extensions)
4. `npm update -g` (AXI/npm tools)
5. `bin/fm-update.sh` from `~/firstmate` (fast-forward only)

**Failure policy:** each step runs independently. A failed step is logged with
its name and the run continues with the next step, so one broken layer (e.g.
the `vlc` cask on Homebrew 6.0.1's missing `command_wrapper` DSL) never blocks
the others. The script exits non-zero if any step failed, so a failed Sunday
run is visible in the log. The nix step pulls the repo first and **never
rebuilds on a stale checkout**: if `git pull --ff-only` fails, that step is
skipped, because rebuilding a stale `configuration.nix` would make
`cleanup = "uninstall"` remove software that newer merged configs declare.

### How the wake works

This Mac sleeps after 1 minute idle, so a scheduled hardware wake is required:

```sh
# one-time, as captain (requires sudo):
sudo pmset repeat wakeorpoweron S 02:55:00   # wake every Sunday 02:55

# verify / remove:
pmset -g sched
sudo pmset repeat cancel                     # remove the schedule
```

The Mac wakes at 02:55, launchd fires the agent at 03:00, and `caffeinate`
holds it awake during the run (it goes back to sleep ~1 min after finishing).
Requirements for the wake to fire: the Mac is **sleeping** (not shut down) and
on **AC power** — a powered-off or battery-only Sunday night means the run is
missed (and launchd catches up the next time the Mac is used, logged then).

### Logs

- `~/Library/Logs/com.bhavesh.auto-update/update-<timestamp>.log` — the run log (newest 30 kept)
- `~/Library/Logs/com.bhavesh.auto-update/launchd.{out,err}.log` — launchd-level capture

### Run manually

```sh
./update-all.sh            # from the repo (works as ~/.dotfiles too)
./update-all.sh --help     # usage + env overrides
```

`AUTO_UPDATE_SKIP_SUDOERS_CHECK=1 ./update-all.sh` skips the sudoers preflight
(testing only — without the scoped sudoers the run would prompt, which the
orchestrator must never do unattended).

### Install & verify the schedule

```sh
mkdir -p ~/Library/LaunchAgents ~/Library/Logs/com.bhavesh.auto-update
cp com.bhavesh.auto-update.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.bhavesh.auto-update.plist
# modern alternative: launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.bhavesh.auto-update.plist

launchctl print gui/$(id -u)/com.bhavesh.auto-update | grep -A6 -E "calendar|next fire"
pmset -g sched     # shows the Sunday 02:55 wake
```

Remove with `launchctl bootout gui/$(id -u)/com.bhavesh.auto-update` + `rm
~/Library/LaunchAgents/com.bhavesh.auto-update.plist`. LaunchAgents run while
you're logged in (a locked screen is fine) but not at the login window, and
the Mac must be sleeping — not powered off — for the pmset wake.

### The sudoers scope (reviewed before install — deliberately narrow)

The orchestrator never prompts, which is only possible because of a scoped
sudoers file. **You install it once, manually** — nothing in the repo ever
installs it. The exact lines, for review (`sudoers/fm-update.sudoers`):

```
bdhaka ALL=(root) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild
bdhaka ALL=(root) NOPASSWD: /usr/sbin/installer
```

```sh
sudo install -m 0440 -o root -g wheel sudoers/fm-update.sudoers /etc/sudoers.d/fm-update
sudo visudo -c -f /etc/sudoers.d/fm-update   # validate
```

That is the **whole scope**: `darwin-rebuild` (the nix-darwin switch) and
`/usr/sbin/installer` (Homebrew pkg casks such as AdGuard run
`sudo installer -pkg … -target /`). No blanket sudo, no `%admin ALL` lines,
no `sudo -i`. If the file is missing or ineffective, `update-all.sh` aborts in
preflight with a clear message instead of ever hanging on a password prompt.

### Microsoft apps stop self-updating

Microsoft AutoUpdate (MAU) is turned off so Microsoft apps (currently
"Windows App") stop silently self-updating; Homebrew/manual installs own them.
One-time, as captain (the key was verified against the installed MAU
preferences):

```sh
defaults write com.microsoft.autoupdate2 HowToCheck -string "Manual"
defaults read com.microsoft.autoupdate2 HowToCheck    # → Manual
# optional, stronger: disable MAU's background agent
# sudo launchctl disable system/com.microsoft.update.agent
```

Re-enable later with `HowToCheck` = `AutomaticCheck`. See `registry.md` for
the full app & plugin registry (what's installed and how each thing updates).

### Japan VPS variant

`update-all-jp.sh` is the same orchestrator for the Japan server
(`root@142.91.108.254`): pi, firstmate, herdr, on **cron** (no launchd, never
sleeps, no sudoers needed — it runs as root). Ship the file + docs only; the
captain deploys when he decides (one `cron` line, documented in the script).

## Make it yours

This repo is mine.
If you clone it, review these before you run `bootstrap.sh`:

- **Username**: run `./bootstrap.sh` (it detects your macOS username and offers to set it) OR change the single `user = "kunchen"` line in `flake.nix`.
  Everything else (`configuration.nix`, `home.nix`, home directory paths) is threaded from that one variable.
- **Host label** `"mac"`, in three places: `flake.nix` (the `darwinConfigurations."mac"` name), `rebuild.sh:5` (the `#mac` at the end of the flake reference), and `bootstrap.sh`'s first-switch command (also `#mac`).
  All three have to match.
- **CPU architecture**, `hostPlatform` in `configuration.nix` (see Prerequisites above).

**Git identity:** this config deliberately does not set your git name or email.
Git will stop your first commit and tell you to set them (`git config --global user.name "Your Name"` and `git config --global user.email you@example.com`).
If you'd rather manage that declaratively, add this back to `home.nix` with your own identity:

```nix
programs.git = {
  enable = true;
  settings.user = {
    name = "Your Name";
    email = "you@example.com";
  };
};
```

**Homebrew cleanup warning:** `configuration.nix` sets `homebrew.onActivation.cleanup = "uninstall"`, with the `--force` flag via `onActivation.extraFlags`.
That means every time you switch, Homebrew removes any package or cask on your machine that isn't listed in the `brews` and `casks` arrays in `configuration.nix`.
If you already have Homebrew stuff installed that isn't in that list, the first switch will uninstall it.
Read through `brews` and `casks` before you run `bootstrap.sh` or `rebuild.sh` for the first time, and add anything you want to keep.

**About `herdr`:** it's in the `brews` list.
It's a real public Homebrew formula (`brew info herdr` finds it in homebrew-core, no tap needed), so it will install fine.
If you don't use it, just remove it from `brews` in your copy.

**Heads-up:**

- `home/AGENTS.md` is my personal agent policy, and `home.nix` installs it for Claude, Codex, and opencode.
  If you clone this repo, you'd silently inherit my agent instructions - edit or delete `home/AGENTS.md` if you don't want that.
- The `cc` and `co` shell aliases in `home.nix` are high-agency shortcuts: `claude --dangerously-skip-permissions` and `codex --full-auto`.
  They're convenient for me, but know what they do before you use them.

## Repo tour

- `flake.nix` - the entry point.
  Wires up nixpkgs, nix-darwin, home-manager, and nix-homebrew, and declares the `mac` machine.
- `configuration.nix` - system-level config: macOS defaults, Homebrew.
- `home.nix` - user-level config: shell, packages, prompt, and the symlinks described below.
- `rebuild.sh` - re-applies the config after the first switch.
  Run this every time you make a change.
- `home/` - the actual config files that get symlinked into place; the sections below explain the shared symlink model and Pi's narrower selective setup.

## How the symlinks work

The files under `home/` are the real files - editing them here is editing your live config, no rebuild needed to see the change in your editor.
`home.nix` uses `mkOutOfStoreSymlink` to point paths like `~/.config/nvim` straight at `home/.config/nvim` in this repo, so the two never drift out of sync.
You only run `./rebuild.sh` when you change something that isn't just a symlinked file, like a package list or a system default.

## Optional Pi configuration

Pi is an opt-in CLI, not a dependency this repository vendors. Install it from its owner with the [official Pi instructions](https://pi.dev), for example:

```sh
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
```

[Pi Launcher](https://github.com/kunchenguid/homebrew-tap) is also optional and installed from its owner, not declared by this config:

```sh
brew install --cask kunchenguid/tap/pi-launcher
```

Home Manager owns exactly two repository-authored Pi directories: `~/.pi/agent/themes` and `~/.pi/agent/extensions`. It also links `models.json` and `settings.json` as individual files. The local extension directory is for public, repository-authored extensions only - third-party package code never belongs there. Run `/reload` after editing a local extension or other Pi resources. The terminal-title extension shows a spinner while Pi is working, then a completion mark with the session name or current directory. The `rose-pine-moon` theme was authored clean-room from the public [Rosé Pine Moon palette](https://rosepinetheme.com/palette) and Pi's [public theme schema](https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json), not from a private or live theme file.

Pi's package system declares two third-party sources in the linked global `settings.json`:

- `npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6` - the exact public npm release from `ryan_nookpi`.
- `git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055` - the exact public `algal` commit for experimental OpenAI server-side compaction.

The version and commit are immutable pins, so Pi does not move them during package updates. Deliberate updates require a new source and security audit, followed by an explicit pin change in `home/.pi/agent/settings.json`. On Pi 0.82.0, global settings declarations install missing pinned packages automatically at startup. No one-time install command is required. Pi keeps the downloaded npm and git package trees in its own unmanaged `~/.pi/agent/npm` and `~/.pi/agent/git` runtime directories, outside Home Manager and Git tracking.

Both packages execute with your full user permissions and must be trusted like any other executable code. The compaction package is experimental, sends the relevant OpenAI compaction and continuity data to OpenAI, and upstream declares the stale peer range `>=0.80.9 <0.81.0`; this exact immutable ref was locally proven to load and perform remote compaction on Pi 0.82.0. Do not treat that proof as a guarantee for a different Pi version or a different package ref.

Home Manager deliberately does not manage `~/.pi/agent` itself, or Pi authentication, sessions, trust decisions, caches, npm/git package trees, or any other runtime state. The model overrides contain no credentials or endpoint settings, do not choose a default model, and only take effect after you authenticate Pi yourself. This remains an additive post-video layer: it does not install Pi, a launcher, or package source code into this repository.

## Notes

The first time you launch `nvim`, it bootstraps [lazy.nvim](https://github.com/folke/lazy.nvim) by cloning plugins from GitHub.
That needs network access once; after that it's offline.
Neovim and WezTerm both use the rose-pine moon theme.
Neovim keeps italics off and uses a transparent background on macOS, Windows, and WSL so it matches the terminal setup.

## License

This repo is licensed under MIT No Attribution.
See `LICENSE`.

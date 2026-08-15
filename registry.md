# Machine & update registry

The single registry answering **"what runs on this machine and how it gets
updated"**. Keep this file in sync whenever the installed set changes (new
brew package, new pi extension, new npm global, new server tool).

The Mac's weekly orchestrator is `update-all.sh` (launchd, Sunday 03:00 —
see README "Automatic updates"). The Japan VPS variant is `update-all-jp.sh`
(cron). Layer order below = step order in the orchestrators.

## How each layer updates

| Layer | Update command | Mac step | Japan step |
|---|---|---|---|
| Homebrew formulae | `brew upgrade` | 1 (brew) | — (not on Japan) |
| Homebrew casks | `brew upgrade` (pkg casks via `/usr/sbin/installer` NOPASSWD) | 1 (brew) | — |
| Nix flake inputs + nix-darwin/home-manager | `nix flake update` + `./rebuild.sh` | 2 (nix) | — |
| Pi + pi extensions | `pi update --all` | 3 (pi) | 1 (pi) |
| npm globals (/opt/homebrew) | `npm update -g` | 4 (npm) | optional |
| firstmate + secondmates | `$HOME/firstmate/bin/fm-update.sh` (fast-forward only) | 5 (firstmate) | 2 (firstmate) |
| herdr | `brew upgrade` on Mac; `herdr update` on Japan | 1 (brew) | 3 (herdr) |
| no-mistakes | `no-mistakes update` — **manual only**, it resets the shared daemon | — | — |
| Microsoft apps (MAU) | `HowToCheck=Manual` — no self-updates; update manually | one-time | — |

## Homebrew — formulae (Mac)

Declared in `configuration.nix` → `homebrew.brews`. Updated by `brew upgrade`.

- `gh` — GitHub CLI (firstmate's GitHub operations run through gh-axi, which wraps gh)
- `herdr` — terminal workspace manager (brew install is canonical; the adhoc-signed
  `~/.local/bin/herdr` shadow was deleted 2026-08-15)
- `nextdns` — DNS daemon (`/Library/LaunchDaemons/nextdns.plist`, `/etc/nextdns.conf`)
- `node` — Node.js runtime (v26.x, arm64)
- `tmux`

Everything else in `brew list --formula` is a transitive dependency of these
(ada-url, brotli, c-ares, … merve is a node dep, simdjson/simdutf are herdr deps).

## Homebrew — casks (Mac)

Declared in `configuration.nix` → `homebrew.casks` (as captured). Updated by
`brew upgrade`.

- `adguard` — **Pkg cask**: upgrade runs `sudo /usr/sbin/installer -pkg … -target /`
  → this is why the scoped sudoers grants `/usr/sbin/installer` NOPASSWD.
- `baby-menu` — from the `kunchenguid/tap` tap (declared in `homebrew.taps`).
- `stremio`, `telegram`, `wezterm`, `whatsapp`
- `vlc` — **NOT brew-managed today**: the brew cask fails on Homebrew 6.0.1
  (missing `command_wrapper` cask DSL, same bug as alex313031-thorium).
  Installed manually from the get.videolan.org DMG (3.0.23, sha256 verified).
  Update it manually until Homebrew or the cask recovers; a failing `brew
  upgrade` on it is logged as a brew-step failure and the other steps continue.

## Nix (Mac)

`flake.nix` inputs: nixpkgs, nix-darwin, home-manager (+ nix-homebrew). Locked
in `flake.lock` — `nix flake update` rewrites it (the working tree then has an
uncommitted `flake.lock`; the captain reviews and commits after the Sunday run).
`./rebuild.sh` runs `sudo … darwin-rebuild switch --flake ~/.dotfiles#mac`
(the scoped sudoers NOPASSWD is what makes this unattended).

User packages from home-manager (`/etc/profiles/per-user/bdhaka/bin`): rg, fd,
fzf, jq, lazygit, nvim, starship, zsh, Hack Nerd Font.

## Pi + pi extensions (Mac and Japan)

`pi list` is authoritative. Updated by `pi update --all` (non-interactive when
no TTY, e.g. under launchd).

| Source | Version pin | Updates? |
|---|---|---|
| `npm:pi-web-access@0.14.0` | latest | yes — moves with `pi update --all` |
| `npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6` | immutable pin in `home/.pi/agent/settings.json` | **no** — deliberately pinned; moves only when the captain changes the pin (README "Optional Pi configuration") |
| `git:github.com/algal/pi-openai-server-compaction@c6d5930…` | immutable commit pin | **no** — same deliberate pin policy |

## npm globals (Mac, prefix `/opt/homebrew`)

Updated by `npm update -g`. Exact set (2026-08-15, from `npm ls -g --depth=0`):

- `@earendil-works/pi-coding-agent` — pi itself (also handled by `pi update --all`)
- `acpx` — AXI CLI executor (pi's tool-call runner)
- `chrome-devtools-axi` — browser automation AXI
- `gh-axi` — GitHub operations AXI (per firstmate rules: "Use gh-axi for GitHub operations")
- `gnhf` — generic node harness helper (firstmate tooling)
- `lavish-axi` — whiteboard/visual AXI
- `pi-acp` — pi agent-connectivity provider (baby-menu's embedded agent)
- `quota-axi` — quota/usage AXI
- `tasks-axi` — task tracking AXI

`no-mistakes` is **not** npm — it is a standalone binary at
`~/.no-mistakes/bin/no-mistakes` (symlinked at `/opt/homebrew/bin/no-mistakes`).
It updates itself with `no-mistakes update`, which **resets the daemon** — so it
is deliberately left OUT of the auto-update pipeline (the daemon is shared and
must never be restarted by an unattended run).

## firstmate (Mac: `/Users/bdhaka/firstmate`)

`bin/fm-update.sh` — self-update of firstmate + registered secondmates,
**fast-forward only** (never force, never merge commits; "already current" is a
success with exit 0). Note: it fetches from origin over ssh, so it needs the
ssh agent/keychain if the key has a passphrase — under launchd there is no
agent, so a passphrase-protected key makes this step log a failure (the other
steps continue).

## Microsoft AutoUpdate (Mac)

`defaults write com.microsoft.autoupdate2 HowToCheck -string "Manual"`
(verified key: `defaults read com.microsoft.autoupdate2 HowToCheck` — was
`AutomaticCheck` before the captain applies it). Microsoft apps (currently
"Windows App", formerly Microsoft Remote Desktop) stop silently self-updating;
update them manually. Optional stronger step: disable the system LaunchAgent
`/Library/LaunchAgents/com.microsoft.update.agent.plist`.

## Apps outside brew/nix (Mac — manual update)

- `Discord.app` — manual download (matches the `discord` cask if ever adopted)
- `NextDNS.app` — App Store (no cask exists)
- Safari web apps (YouTube, Gmail - bhavesh.net, Google Gemini) — re-created via
  Safari "Add to Dock"; updated by the web app itself

## Japan VPS (`root@142.91.108.254` — `update-all-jp.sh` via cron)

Never sleeps, no launchd, runs as root (no sudoers needed). Layers: pi,
firstmate (`/root/firstmate`), herdr (0.8.0 — also the t.1ed.ge web-terminal
backend at `/root/.config/herdr/herdr.sock`). See `update-all-jp.sh` and the
README "Japan VPS variant" section. Assumptions (verify on the server before
first run): pi and herdr on PATH, firstmate at `/root/firstmate`.

{ user, ... }:

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel CPU

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };
  system.stateVersion = 6;
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = true;  # auto-hide the menu bar
      AppleShowAllExtensions = true;
    };
    dock.autohide = true;
    # Dock look captured from live system 2026-08-15.
    dock.tilesize = 53;
    dock.magnification = true;
    dock.largesize = 97;
    dock.show-process-indicators = false;  # "Show indicators for open apps" off (captain 2026-08-15)
    # Custom pins (beyond default apps): Safari web apps + Discord + Passwords + WezTerm.
    # Note: Safari web apps (YouTube/Gmail/Gemini) themselves are NOT
    # declarable — they must be re-added via Safari "Add to Dock" after a
    # fresh install; these pins are best-effort.
    # Updated 2026-08-15: removed TextEdit+Preview, added Passwords+WezTerm.
    dock.persistent-apps = [
      "/System/Applications/Passwords.app"
      "/Applications/Discord.app"
      "/Applications/WezTerm.app"
    ];
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click
  };
  nix-homebrew = {
    enable = true;
    autoMigrate = true;
    inherit user;
  };
  homebrew = {
    enable = true;
    # cleanup = "uninstall" is intentional and permanent (captain decision
    # 2026-08-15): every switch uninstalls any formula/cask not declared
    # below, so anything installed on this machine must be declared here.
    # Do NOT change this to "zap" or "none".
    onActivation.cleanup = "uninstall";
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" ];
    taps = [
      "kunchenguid/tap"   # required for the baby-menu cask (homebrew-tap)
    ];
    brews = [
      "gh"
      "herdr"
      "nextdns"
      "node"
      "tmux"
      "ffmpeg"  # audio/video tools (re-declared: removed by the 2026-08-15 stale-checkout rebuild)
      "yt-dlp"  # video downloader (re-declared: removed by the 2026-08-15 stale-checkout rebuild)
      "deno"    # JS/TS runtime (re-declared: removed by the 2026-08-15 stale-checkout rebuild)
    ];
    casks = [
      "adguard"
      "baby-menu"
      "google-chrome"  # browser automation (re-declared: removed by the 2026-08-15 stale-checkout rebuild)
      "stremio"
      "telegram"
      "whatsapp"
      "wezterm"
      "windows-app"  # Microsoft Windows App 11.3.8 (installs on next rebuild)
      # "vlc"  # stays a manual DMG install (3.0.23, get.videolan.org) until the
      # command_wrapper bug in nix-pinned brew 6.0.1 is fixed upstream - the cask
      # aborts brew bundle (exit 1) at every switch. Not brew-managed; cleanup
      # never removes it. Declare once the cask evaluates cleanly.
    ];
  };
}

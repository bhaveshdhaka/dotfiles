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
    # SAFETY: zap was disabled 2026-08-15 until the config declares the real
    # system (gh, nextdns, tmux, node, adguard, baby-menu, etc.).
    # Re-enable only after inventory+adoption lands.
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
    ];
    casks = [
      "adguard"
      "baby-menu"
      "telegram"
      "whatsapp"
      "wezterm"
    ];
  };
}

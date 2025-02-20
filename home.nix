{ config, pkgs, lib, specialArgs, ... }:
let
  isGraphical = specialArgs.isGraphical;
  agenix = specialArgs.agenix;
  unstable = specialArgs.unstable;

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    ipython
    pandas
    matplotlib
    seaborn
    pyyaml
    boto3
  ]);
  vim-with-custom-rc = pkgs.vim_configurable.customize {
    vimrcConfig = {
      customRC = ''
        filetype plugin indent on
        syntax on
        set number relativenumber
        set tabstop=4
        set softtabstop=4
        set expandtab
        set shiftwidth=4
        set smarttab
        set clipboard=unnamed
        set noerrorbells
        set vb t_vb=
        colorscheme torte
      '';
    };
  };
in {
  programs.home-manager.enable = true;

  programs.fish = import ./fish.nix {inherit pkgs isGraphical;};

  home.packages = with pkgs; [
    git
    unstable.emacs
    ripgrep # for project-wide search in emacs
    fzf # for reverse history search in fish shell
    wget
    bat
    git
    tree
    zip
    unzip
    nmap
    gnupg
    sl
    htop
    file
    iotop
    jq
    pythonEnv
    rxvt_unicode
    kitty
    xclip
    vim-with-custom-rc
    broot
    unstable.zellij
    pgbackrest
    agenix.packages.${system}.agenix
    nix-tree
    qrencode
    rclone
    restic
    awscli2
    bashmount
    docker
    taskwarrior
    pgcli
  ] ++ (if isGraphical then [
    arandr
    dconf # Required for gtk3 configuration
    wmctrl
    chromium
    unstable.firefox
    vlc
    pulsemixer
    libreoffice
    simplescreenrecorder
    qgis
    unstable.slack
    unstable.zoom-us
    pkgs.gnomeExtensions.appindicator
    pkgs.gnomeExtensions.paperwm
    pkgs.gnomeExtensions.switcher
  ] else []);

  # dotfiles
  home.file.".doom.d/config.el".source   = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.doom.d/config.el";
  home.file.".doom.d/init.el".source     = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.doom.d/init.el";
  home.file.".doom.d/packages.el".source = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.doom.d/packages.el";

  # For graphical environments
  home.file.".xmonad/xmonad.hs".source = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.xmonad/xmonad.hs";
  home.file.".xmobarrc".source = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.xmobarrc";
  home.file.".Xresources".source = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.Xresources";
  home.file.".config/urxvt/ext/resize-font".source = "${pkgs.fetchFromGitHub {
    owner = "simmel";
    repo = "urxvt-resize-font";
    rev = "b5935806f159594f516da9b4c88bf1f3e5225cfd";
    sha256 = "sha256-Q/nSa3NMKoBubS0Xpoh+Am84ikUsgNrcUM2WoobepM4=";
  }}/resize-font";

  services.dunst = {
    enable = isGraphical;
    settings = {
      global = {
        width = 600;
        height = 600;
        offset = "30x50";
        origin = "top-right";
        transparency = 10;
        frame_color = "#eceff1";
        font = "Droid Sans 26";
      };

      urgency_normal = {
        background = "#37474f";
        foreground = "#eceff1";
        timeout = 3;
      };
    };
  };

  dconf.enable = true;
  dconf.settings = {
    "org/gnome/desktop/peripherals/keyboard" = {
      delay = lib.hm.gvariant.mkUint32 200;
      repeat-interval = lib.hm.gvariant.mkUint32 28;
      repeat = true;
    };
    "org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions = with pkgs.gnomeExtensions; [
        appindicator.extensionUuid
        paperwm.extensionUuid
        switcher.extensionUuid
        system-monitor.extensionUuid
        workspace-indicator.extensionUuid
      ];
    };
    "org/gnome/desktop/wm/preferences" = {
      num-workspaces = lib.hm.gvariant.mkInt32 6;
      workspace-names = [ "1" "2" "3" "4" "5" "6" ];
      audible-bell = lib.hm.gvariant.mkBoolean false;
    };
    "org/gnome/desktop/wm/keybindings" = {
      switch-to-workspace-1 = [ "<Super>1" ];
      switch-to-workspace-2 = [ "<Super>2" ];
      switch-to-workspace-3 = [ "<Super>3" ];
      switch-to-workspace-4 = [ "<Super>4" ];
      switch-to-workspace-5 = [ "<Super>5" ];
      switch-to-workspace-6 = [ "<Super>6" ];
      move-to-workspace-1 = [ "<Shift><Super>1" ];
      move-to-workspace-2 = [ "<Shift><Super>2" ];
      move-to-workspace-3 = [ "<Shift><Super>3" ];
      move-to-workspace-4 = [ "<Shift><Super>4" ];
      move-to-workspace-5 = [ "<Shift><Super>5" ];
      move-to-workspace-6 = [ "<Shift><Super>6" ];
      minimize = [ ];
    };
    "org/gnome/shell/keybindings" = {
      switch-to-application-1 = [ ];
      switch-to-application-2 = [ ];
      switch-to-application-3 = [ ];
      switch-to-application-4 = [ ];
      switch-to-application-5 = [ ];
      switch-to-application-6 = [ ];
    };
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      binding = "<Control><Super>Return";
      command = "kitty";
      name = "new-terminal";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1" = {
      binding = "<Control>m";
      command = "/home/rowan/machine-configuration/scripts/toggle_mic_mute.sh";
      name = "toggle-mic-mute";
    };
  };

  home.stateVersion = "21.11";
}

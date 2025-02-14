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
    "org/gnome/desktop/background" = {
      picture-options = "none";
      primary-color = "#000000";
    };
  };

  home.stateVersion = "21.11";
}

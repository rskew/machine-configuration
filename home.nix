{ config, pkgs, unstable, specialArgs, ... }:
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
  set-theme-dark = pkgs.writeShellScriptBin "dark" ''
    printf '\033]10;white\007' # urxvt set foreground
    printf '\033]11;black\007' # urxvt set background
    sed -i 's/^\(URxvt.background\).*$/URxvt.background: black/' $(realpath ~/.Xresources)
    sed -i 's/^\(URxvt.foreground\).*$/URxvt.foreground: white/' $(realpath ~/.Xresources)
    sed -i 's/^\(URxvt.pointerColor2\).*$/URxvt.pointerColor2: #ffffff/' ~/.Xresources
    xrdb -load ~/.Xresources
    echo dark > ~/.current-theme
  '';
  set-theme-light = pkgs.writeShellScriptBin "light" ''
    printf '\033]10;#383a42\007' # urxvt set foreground
    printf '\033]11;#f9f9f9\007' # urxvt set background
    sed -i 's/^\(URxvt.background\).*$/URxvt.background: #f9f9f9/' $(realpath ~/.Xresources)
    sed -i 's/^\(URxvt.foreground\).*$/URxvt.foreground: #383a42/' $(realpath ~/.Xresources)
    sed -i 's/^\(URxvt.pointerColor2\).*$/URxvt.pointerColor2: #000000/' ~/.Xresources
    xrdb -load ~/.Xresources
    echo light > ~/.current-theme
  '';
  vim = pkgs.writeShellScriptBin "vim" ''
    if `grep light ~/.current-theme`
    then
      ${vim-with-custom-rc}/bin/vim -c 'colorscheme zellner' $@
    else
      ${vim-with-custom-rc}/bin/vim $@
    fi
  '';
  bat-themed = pkgs.writeShellScriptBin "bat" ''
    if `grep light ~/.current-theme`
    then
      ${pkgs.bat}/bin/bat --theme 'Monokai Extended Light' $@
    else
      ${pkgs.bat}/bin/bat $@
    fi
  '';
in {
  programs.home-manager.enable = true;

  programs.fish = import ./fish.nix {inherit pkgs isGraphical;};

  home.packages = with pkgs; [
    git
    unstable.emacs
    ripgrep # for project-wide search in emacs
    fzf # for reverse history search in fish shell
    wget
    bat-themed
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
    any-nix-shell
    byobu
    tmux
    rxvt_unicode
    set-theme-dark
    set-theme-light
    vim
    broot
    unstable.pandoc
    unstable.zellij
    pgbackrest
    agenix.packages.${system}.agenix
    nix-tree
  ] ++ (if isGraphical then [
    arandr
    dconf # Required for gtk3 configuration
  ] else []);

  # dotfiles
  home.file.".doom.d/config.el".source   = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.doom.d/config.el";
  home.file.".doom.d/init.el".source     = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.doom.d/init.el";
  home.file.".doom.d/packages.el".source = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.doom.d/packages.el";

  # For graphical environments
  home.file.".xmonad/xmonad.hs".source = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.xmonad/xmonad.hs";
  home.file.".xmobarrc".source = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.xmobarrc";
  home.file.".Xresources".source = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.Xresources";

  #gtk = {
  #  enable = true;
  #  font.name = "Sans 16"; # make firefox font big for hi-res monitor
  #  cursorTheme = {
  #    name = "Adwaita";
  #    size = 40; # make cursor big for hi-res monitor
  #  };
  #};

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

  home.stateVersion = "21.11";
}

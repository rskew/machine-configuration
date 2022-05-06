{config, pkgs, isRemote ? false, ...}: {
  programs.home-manager.enable = true;

  programs.fish = import ./fish.nix { inherit pkgs isRemote; };

  programs.vim = {
    enable = true;
    extraConfig = ''
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

  # TODO Why are none of these packages installed?
  #home.packages = with pkgs; [
  #  unstable.emacs
  #  ripgrep # for project-wide search in emacs
  #  fzf # for reverse history search in fish shell
  #  wget
  #  bat
  #  git
  #  tree
  #  rxvt_unicode
  #  zip
  #  unzip
  #  nmap
  #  gnupg
  #  sl
  #  htop
  #  file
  #  iotop
  #  jq
  #  rclone
  #  restic
  #  pythonEnv
  #] ++ (if isRemote then [] else [
  #  gnome3.dconf # Required for gtk3 configuration
  #]);

  # dotfiles
  home.file.".doom.d/config.el".source   = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.doom.d/config.el";
  home.file.".doom.d/init.el".source     = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.doom.d/init.el";
  home.file.".doom.d/packages.el".source = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.doom.d/packages.el";
} // (if isRemote then {} else {
  gtk = {
    enable = true;
    font.name = "Sans 20"; # make firefox font big for hi-res monitor
    cursorTheme = {
      name = "Adwaita";
      size = 40; # make cursor big for hi-res monitor
    };
  };
  home.file.".xmonad/xmonad.hs".source   = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.xmonad/xmonad.hs";
  home.file.".xmobarrc".source           = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.xmobarrc";
  home.file.".Xresources".source         = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.Xresources";
})

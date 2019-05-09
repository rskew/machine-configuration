# Laptop config

# To update run
# sudo -HE nixos-rebuild switch

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.efiSupport = true;
  # boot.loader.grub.efiInstallAsRemovable = true;
  # boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.grub.device = "/dev/sda"; # or "nodev" for efi only

  networking.hostName = "ro-X1";
  networking.networkmanager.enable = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n = {
    consoleFont = "source-code-pro";
    consoleKeyMap = "us";
    defaultLocale = "en_AU.UTF-8";
  };

  # Set your time zone.
  time.timeZone = "Australia/Melbourne";

  nixpkgs.config = {
    # hackage-packages was broken on unstable, give it a go anyway?
    allowBroken = true;
  
    # Create an alias for the unstable channel
    packageOverrides = pkgs: with pkgs; {
      unstable = import <nixos-unstable> {
        # pass the nixpkgs config to the unstable alias
        config = config.nixpkgs.config;
      };
      # Don't run tests for Haskell packages
      haskellPackages = pkgs.haskellPackages.override {
        overrides = self: super: {
          ghc-syb-utils = pkgs.haskell.lib.dontCheck super.ghc-syb-utils;
          #cabal = pkgs.haskellPackages.cabalNoTest;
        };
      };
    };
  };
  
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
    vimHugeX
    ctags
    bat
    emacs
    feh
    git
    tree
    xbindkeys
    xcompmgr
    xlibs.xmodmap
    xlibs.xev
    xlibs.xinput
    xlibs.xmessage
    fish
    sqlite
    rxvt_unicode
    firefox
    pandoc
    i3lock
    trayer
    networkmanagerapplet
    vlc
    xclip
    haskellPackages.xmobar
    pavucontrol
    pinta
    inkscape
    zip
    unzip
    nmap
    gnupg
    bc
    imagemagick
    xorg.xbacklight
    killall
    jdk
    awscli
    xorg.xdpyinfo
    #######
    # Can't get glxinfo to work
    glxinfo
    #unstable.intel-media-driver
    #unstable.mesa
    #######
    pstree
    sl
    wirelesstools
    cowsay
    # For browser-media-keys firefox addon,
    # supposedly lets media keys work when browser not in focus
    xorg.xcbutilkeysyms
    htop
    hunspell
    (import (fetchGit "https://github.com/haslersn/fish-nix-shell"))
    nodePackages.bower
    nodePackages.pulp
    unstable.nodePackages.parcel-bundler
    gnumake
    gcc
    chromium
    redshift
    iftop
    vnstat
    binutils-unwrapped
    nix-index
    nodejs
    msr-tools
    unstable.zoom
    meshlab
    nix-prefetch-git
    conda
    lolcat
    figlet
    # Haskell stuff, should use nix-shells for this
    ghc
    cabal-install
    unstable.haskellPackages.stack
    haskell.compiler.ghcjs
  ];

  services.vnstat.enable = true;

  fonts.fonts = with pkgs; [
    source-code-pro
  ];

  programs.fish.enable = true;
  programs.fish.promptInit = ''
    fish-nix-shell --info-right | source
  '';

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.mtr.enable = true;
  programs.gnupg.agent = { enable = true; enableSSHSupport = true; };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  services.printing.enable = true;

  sound.enable = true;
  hardware.pulseaudio.enable = true;

  # Can't seem to get glxinfo working :/
  hardware.opengl.enable = true;

  services.xserver = {

    enable = true;
    layout = "us";

    # Enable touchpad support.
    libinput.enable = true;

    desktopManager.xterm.enable = false;

    windowManager.xmonad = {
      enable = true;
      enableContribAndExtras = true;
      extraPackages = haskellPackages: [
        haskellPackages.xmonad-contrib
        haskellPackages.xmonad-extras
        haskellPackages.xmonad
      ];
    };
    windowManager.default = "xmonad";
    # This used to me my .xinitrc
    displayManager.sessionCommands = with pkgs; lib.mkAfter
      ''
      xbindkeys
      
      xrdb -merge /home/rowan/.Xresources
      xmodmap /home/rowan/.Xmodmap
      
      xset s off
      xset -dpms
      xset s noblank 
      
      trayer --edge bottom \
             --align right \
             --SetDockType true \
             --SetPartialStrut true \
             --expand true \
             --width 4 \
             --transparent true \
             --tint 0x000000 \
             --height 20 \
             --monitor "primary" &
      
      exec nm-applet &
      exec redshift &
      
      feh --bg-scale ~/Pictures/jupyter_near_north_pole.jpg &
      xcompmgr -c &
      
      emacs --daemon &
      '';
    };

  users.users.rowan = {
    isNormalUser = true;
    home = "/home/rowan";
    uid = 1000;
    extraGroups = [ "wheel" "networkmanager" "audio" ];
    shell = "/run/current-system/sw/bin/fish";
  };

  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "18.09"; # Did you read the comment?

  services.redshift = {
    enable = true;
    # Melbourne
    latitude = "-37.8136";
    longitude = "144.9631";
  };

  # This X1 won't wake up from sleep, hibernate instead
  services.logind.extraConfig = "HandleLidSwitch=hibernate";

  systemd.services.lockScreenOnWake = { 
    description = "Lock screen on wakeup";
    wantedBy = [ "hibernate.target" ];
    before = [ "hibernate.target" ];
    path = with pkgs; [ i3lock ];
    serviceConfig = {
      Environment = "DISPLAY=:0";
      User = "rowan";
    };
    script = ''
      /home/rowan/scripts/lock.sh
    '';
    serviceConfig.Type = "forking";
  };

}

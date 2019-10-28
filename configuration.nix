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
  boot.loader.grub.device = "/dev/sda"; # or "nodev" for efi only

  networking.hostName = "ro-X1";
  networking.networkmanager.enable = true;

  sound.enable = true;
  hardware.pulseaudio.enable = true;
  hardware.pulseaudio.support32Bit = true;

  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
      intel-media-driver # only available starting nixos-19.03 or the current nixos-unstable
    ];
  };

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
    #allowUnfree = true;

    # For qgis
    allowBroken = true;

    # Create an alias for the unstable channel
    packageOverrides = pkgs: with pkgs; {
      unstable = import <nixos-unstable> {
        # pass the nixpkgs config to the unstable alias
        config = config.nixpkgs.config;
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
    xorg.xdpyinfo
    killall
    jdk
    awscli
    pstree
    sl
    wirelesstools
    cowsay
    htop
    hunspell
    (import (fetchGit "https://github.com/haslersn/fish-nix-shell"))
    ####
    # Purescript dev stuff
    nodePackages.bower
    nodePackages.pulp
    unstable.nodePackages.parcel-bundler
    # install purescript and spago using
    #   https://github.com/justinwoo/easy-purescript-nix
    ####
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
    zoom
    meshlab
    nix-prefetch-git
    lolcat
    figlet
    fzf
    gparted
    ripgrep
    file
    patchelf
    nmap
    unstable.qgis
    dfu-util
    ldns
    xournal
    bashmount
    filelight
    iotop
    inform7
    frotz
    maven
    # Satellite/Radio stuff
    gpredict
    python36
    arduino
    hamlib
    ####
    ## Haskell stuff
    #haskell.compiler.ghc822
    #ghc
    #cabal-install
    #haskellPackages.stack
    #haskellPackages.Agda
    ####
    dos2unix
    docker
    docker_compose
    jq
    openvpn
    plover.stable
    conda
    glxinfo
    libva-utils
    libva
    libspatialite
    spatialite_tools
  ];

  virtualisation.docker.enable = true;
  virtualisation.docker.enableOnBoot = true;

  services.vnstat.enable = true;

  fonts.fonts = with pkgs; [
    source-code-pro
  ];

  #fonts.fontconfig.dpi=180;

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
  networking.firewall.allowedTCPPorts = [
    8111 # workflow fileserver
    8112 # workflow websocket
  ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  services.printing.enable = true;

  hardware.brightnessctl.enable = true;

  services.xserver = {

    enable = true;
    layout = "us";

    # Enable touchpad support.
    libinput.enable = true;

    desktopManager.xterm.enable = false;

    xkbOptions = "ctrl:nocaps";

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
    # what used to be .xinitrc
    displayManager.sessionCommands = with pkgs; lib.mkAfter
      ''
      xbindkeys
      
      xrdb -merge /home/rowan/.Xresources
      #xmodmap /home/rowan/.Xmodmap
      #setxkbmap -option ctrl:nocaps
      
      # turn off Display Power Management Service (DPMS)
      xset -dpms
      setterm -blank 0 -powerdown 0

      # turn off black Screensaver
      xset s off

      
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

  # Make the `usb` group for read/write permissions to usb devices
  users.groups.usb = {};
  services.udev.extraRules = ''
    KERNEL=="*", SUBSYSTEMS=="usb", MODE="0664", GROUP="usb"
  '';

  users.users.rowan = {
    isNormalUser = true;
    home = "/home/rowan";
    uid = 1000;
    extraGroups = [ "wheel" "networkmanager" "audio" "usb" "fuse" "video" ];
    shell = "/run/current-system/sw/bin/fish";
  };

  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "19.03"; # Did you read the comment?

  services.redshift = {
    enable = true;
  };

  # Melbourne
  location = {
    latitude = -37.8136;
    longitude = 144.9631;
  };

  # This X1 won't wake up from sleep, hibernate instead
  services.logind.lidSwitch = "hibernate";

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

# Laptop config

# To update run
# sudo -HE nixos-rebuild switch

{ config, pkgs, ... }:

let
  easy-ps = import (pkgs.fetchFromGitHub {
    owner = "justinwoo";
    repo = "easy-purescript-nix";
    # version has purs 0.13.4, spago 0.10.0.0
    rev = "aa94aeac3a6ad9b4dfa0e807ad1421097d74f663";
    sha256 = "1kfhi6rscgf165zg4f1s0fgppygisvc7dppxb93n02rypxfxjirm";
  }) {
    inherit pkgs;
  };


  tex = pkgs.texlive.combine {
      inherit (pkgs.texlive) scheme-small xetex lastpage tcolorbox environ trimspaces mdframed needspace efbox lipsum cm-super;
  };
in

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
  hardware.pulseaudio = {
    enable = true;
    support32Bit = true;
    zeroconf.discovery.enable = true;
    # for bluetooth
    package = pkgs.pulseaudioFull;
    extraModules = [ pkgs.pulseaudio-modules-bt ];
  };

  hardware.bluetooth = {
    enable = true;
    config = {
      General = {
        Enable = "Source,Sink,Media,Socket";
      };
    };
    #config = ''
    #  [General]
    #  Enable=Source,Sink,Media,Socket
    #'';
  };
  services.blueman.enable = true;

  # This loads the Broadcom Bluetooth patch that makes
  # HSP/HFP mode work with bluetooth headsets
  hardware.enableAllFirmware = true;

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

  services.upower.enable = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n = {
    defaultLocale = "en_AU.UTF-8";
  };

  console = {
    font = "source-code-pro";
    keyMap = "us";
  };

  # Set your time zone.
  time.timeZone = "Australia/Melbourne";

  nixpkgs.config = {
    # for steam-run?
    # for anydesk
    allowUnfree = true;

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
    tex
    feh
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
    easy-ps.purs
    easy-ps.spago
    ####
    gnumake
    gcc
    chromium
    redshift
    iftop
    vnstat
    nethogs
    binutils-unwrapped
    nix-index
    nodejs
    unstable.zoom-us
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
    bashmount
    filelight
    iotop
    # Satellite/Radio stuff
    ###
    gpredict
    python36
    arduino
    hamlib
    unstable.anydesk
    ###
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
    git-lfs
    glib-networking
    qbittorrent
    libreoffice
    swiProlog
    usbutils
    picocom
    ghostscript
    youtube-dl
    pulsemixer
    # For podman
    podman
    runc
    conmon
    slirp4netns
    fuse-overlayfs
    #
    unstable.nixops
    brightnessctl
    httpie
    ardour
    wtf
    tailscale
    gnome3.zenity
    steam
    shotcut
    # hackasat
    direwolf
    sox
    audacity
    spek
    exiftool
    #
    tightvnc
    arandr
  ];

  virtualisation.virtualbox.host.enable = true;

  virtualisation.libvirtd.enable = true;
  boot.binfmt.emulatedSystems = [ "armv6l-linux" ];

  virtualisation.docker.enable = true;
  virtualisation.docker.enableOnBoot = true;
  # TODO configure docker services that should run on boot
  # - knowwhat
  # - vega-editor

  # Configure podman
  environment.etc."containers/policy.json" = {
    mode="0644";
    text=''
      {
        "default": [
          {
            "type": "insecureAcceptAnything"
          }
        ],
        "transports":
          {
            "docker-daemon":
              {
                "": [{"type":"insecureAcceptAnything"}]
              }
          }
      }
    '';
  };

  environment.etc."containers/registries.conf" = {
    mode="0644";
    text=''
      [registries.search]
      registries = ['docker.io', 'quay.io']
    '';
  };

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
    80 # Wekan
    8085 # knowwhat fileserver
    8086 # knowwhat websocket
    8001 # kimai
  ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Required for libvirtd virtualisation for nixops
  networking.firewall.checkReversePath = false;

  services.tailscale.enable = true;

  services.printing.enable = true;

  services.xserver = {

    enable = true;
    layout = "us";

    # Enable touchpad support.
    libinput = {
      enable = true;
      accelSpeed = "0.2";
    };

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
    displayManager.defaultSession = "none+xmonad";
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
      exec blueman-applet &
      
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
    extraGroups = [ "wheel" "networkmanager" "audio" "usb" "fuse" "video" "dialout" "uucp" "sound" "pulse" "libvirtd" "docker" ];
    shell = "/run/current-system/sw/bin/fish";

    # Doing this because ???
    # https://nixos.wiki/wiki/Podman
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
    
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

  services.restic.backups = {
    remotebackup = {
      paths = [
        # Projects in case github breaks or something
        "/home/rowan/projects/mindmaps"
        "/home/rowan/projects/knowwhat"
        "/home/rowan/projects/modal-synth"
        "/home/rowan/projects/purescript-functorial-data-migration-core"
        "/home/rowan/projects/purescript-halogen-svg"
        "/home/rowan/projects/purescript-knuth-bendix"
        "/home/rowan/projects/purescript-string-rewriting"
        #"/home/rowan/backups"
        #"/home/rowan/fonts"
        # Random stuff
        "/home/rowan/memes"
        "/home/rowan/Pictures"
        "/home/rowan/screenshots"
        #"/home/rowan/space"
        #"/home/rowan/workflow"
        # System configs
        "/etc/nixos"
        # Utilities
        "/home/rowan/.ssh"
        "/home/rowan/.config/fish"
      ];
      repository = "b2:restic-backups-X1-old-mate";
      passwordFile = "/etc/nixos/secrets/restic-password";
      # s3CredentialsFile just gets loaded as the systemd service 
      # EnvironmentFile, nothing particular to S3
      s3CredentialsFile = "/etc/nixos/secrets/restic-b2-appkey.env";
      timerConfig = {
        OnCalendar = "daily";
      };
      initialize = true;
    };
  };

}

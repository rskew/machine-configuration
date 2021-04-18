# Laptop config

# Steps to reproduce laptop state:
# - install nixos
# - add unstable channel with `nix-channel --add https://nixos.org/channels/nixos-unstable nixos-unstable; nix-channel --update`
# - clone this config from github.com/rskew/machine-configuration and follow instructions in README.md as well as:
#   - update boot config for specific machine (e.g. boot.initrd.luks.device)
#   - update networking.hostName
#   - update backup repository for specific machine
# - clone github.com/rskew/dotfiles into ~/
# - clone github.com/rskew/bashscripties to ~/scripts
# - add password files to /etc/nixos/secrets/
#   - restic-password for this machine's restic backup repository
#   - restic-b2-appkey.env with B2_ACCOUNT_ID and B2_ACCOUNT_KEY
# - install doom emacs by cloning the repo to ~/.emacs.d

# To update run
# sudo nixos-rebuild switch

{ config, pkgs, ... }:

let
  easy-ps = import (pkgs.fetchFromGitHub {
    owner = "justinwoo";
    repo = "easy-purescript-nix";
    # this version has purs 0.13.4, spago 0.10.0.0
    rev = "aa94aeac3a6ad9b4dfa0e807ad1421097d74f663";
    sha256 = "1kfhi6rscgf165zg4f1s0fgppygisvc7dppxb93n02rypxfxjirm";
  }) {
    inherit pkgs;
  };

  # Run multiple tailscale daemons using multiple copies of
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/tailscale.nix
  # but giving them differnet socket folders, state folders, and ports.
  # After a tailscale daemon is running, authenticate it with `sudo tailscale up --socket=/var/run/${dir}/tailscaled.sock`
  tailscaled = {port ? "41641", dir ? "tailscale"}: {
    description = "Tailscale client daemon";
    after = [ "network-pre.target" ];
    wants = [ "network-pre.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig = {
      StartLimitIntervalSec = 0;
      StartLimitBurst = 0;
    };
    serviceConfig = {
      ExecStart = "${pkgs.tailscale}/bin/tailscaled --port=${port} --socket=/var/run/${dir}/tailscaled.sock --state=/var/lib/${dir}/tailscale.state --tun=${dir}";
      RuntimeDirectory = dir;
      RuntimeDirectoryMode = 755;
      StateDirectory = dir;
      StateDirectoryMode = 750;
      CacheDirectory = dir;
      CacheDirectoryMode = 750;
      Restart = "on-failure";
    };
  };

  pythonEnv = pkgs.python38.withPackages(ps: with ps; [ 
    pandas 
    matplotlib
    seaborn
  ]);
  # Run xonsh with whatever python environment is active
  xonsh = pkgs.writeShellScriptBin "xonsh" ''
    SHELL_TYPE=best /usr/bin/env python ${pkgs.xonsh}/bin/.xonsh-wrapped
  '';

in
{
  imports =
    [ # Include the results of the hardware scan.
      ../hardware-configuration.nix
    ];

  boot.initrd.luks.devices = {
    root = {
      device = "/dev/sda2";
      preLVM = true;
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.loader.grub = {
    enable = true;
    version = 2;
    efiSupport = true;
    enableCryptodisk = true;
    device = "nodev";
  };

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  networking.interfaces.enp0s31f6.useDHCP = true;
  networking.interfaces.wlp4s0.useDHCP = true;

  networking.hostName = "rowan-yoga-260-keenbean";
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
  };
  services.blueman.enable = true;

  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
      intel-media-driver # only available starting nixos-19.03
    ];
  };

  # Used to create video loopback device that can be fed a webcam feed
  # rotated by ffmpeg
  boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
  boot.kernelModules = [ "v4l2loopback video_nr=22 exclusive_caps=1 card_label='processed_webcam'" ];

  services.upower.enable = true;

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
    # for zoom-us, teams
    allowUnfree = true;

    # Create an alias for the unstable channel
    packageOverrides = pkgs: with pkgs; {
      unstable = import <nixos-unstable> {
        # pass the nixpkgs config to the unstable alias
        config = config.nixpkgs.config;
      };

      vim = pkgs.vim_configurable.customize {
        name = "vim-custom";
        vimrcConfig.customRC = ''
          filetype plugin indent on
          filetype on
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
  };
  
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
    vim
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
    unstable.firefox
    pandoc
    feh
    i3lock
    trayer
    networkmanagerapplet
    vlc
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
    #### Purescript dev stuff
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
    nethogs
    vnstat
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
    dfu-util
    ldns
    bashmount
    filelight
    iotop
    docker
    docker_compose
    jq
    openvpn
    plover.stable
    conda
    glxinfo
    qbittorrent
    libreoffice
    swiProlog
    usbutils
    ghostscript
    youtube-dl
    pulsemixer
    brightnessctl
    ardour
    tailscale
    shotcut
    tightvnc
    arandr
    rclone
    restic
    lazygit
    direnv
    #### used to rotate webcam via loopback video device
    guvcview
    v4l-utils
    ffmpeg
    ####
    unstable.xournalpp
    gnome3.nautilus
    xautolock
    cachix
    sshfs
    unstable.signal-desktop
    gv
    parcellite
    unstable.teams
    simplescreenrecorder
    teyjus
    openscad
    libnotify
    notify-osd
    freecad
    kubectl
    git-lfs
    k9s
    csvkit
    pythonEnv
    xonsh
    qgis
  ];

  virtualisation.docker.enable = true;
  virtualisation.docker.enableOnBoot = true;

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

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [
  ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  systemd.services.tailscale0 = tailscaled { 
    port = "41641";
    dir = "tailscale0";
  };
  systemd.services.tailscale1 = tailscaled { 
    port = "41642";
    dir = "tailscale1";
  };

  services.vnstat.enable = true;

  services.printing.enable = true;

  services.xserver = {

    enable = true;

    layout = "us";

    # Enable touchpad support.
    libinput = {
      enable = true;
      accelSpeed = "0.2";
      naturalScrolling = false;
    };

    desktopManager.xterm.enable = false;

    xkbOptions = "ctrl:nocaps";

    windowManager.xmonad = {
      enable = true;
      enableContribAndExtras = true;
      extraPackages = hp: with hp; [
        xmonad-contrib
        xmonad-extras
        xmonad
      ];
    };
    displayManager.defaultSession = "none+xmonad";
    # what used to be .xinitrc
    displayManager.sessionCommands = with pkgs; lib.mkAfter
      ''
      xbindkeys
      
      xrdb -merge /home/rowan/.Xresources
      
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
             --width 5 \
             --transparent true \
             --tint 0x000000 \
             --height 20 \
             --monitor "primary" &
      
      exec nm-applet &
      exec redshift &
      exec blueman-applet &
      
      feh --bg-scale ~/Pictures/jupyter_near_north_pole.jpg &
      xcompmgr -c &

      touchegg &

      parcellite &

      xautolock -time 10 -locker /home/rowan/scripts/lock.sh -corners 00-0 &

      xkbcomp /etc/nixos/keymap.xkb $DISPLAY
      '';
  };

  services.xserver.wacom.enable = true;
  # Wacom-driver gstures don't seem to work too well, turn them off
  # https://askubuntu.com/questions/1122332/one-finger-scrolling-touchscreen-in-firefox
  environment.etc."X11/xorg.conf.d/50-wacom.conf".text = ''
    Section "InputClass"
        Identifier "Wacom class"
        MatchProduct "Wacom|WACOM|Hanwang|PTK-540WL|ISDv4|ISD-V4|ISDV4"
        MatchDevicePath "/dev/input/event*"
    
        Driver "wacom"
        Option "Gesture" "off"
    EndSection
  '';

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
  };

  nix.trustedUsers = [ "root" "rowan" ];

  services.redshift = {
    enable = true;
  };

  # Melbourne
  location = {
    latitude = -37.8136;
    longitude = 144.9631;
  };

  systemd.services.lockScreenBeforeSleep = { 
    description = "Lock screen before sleep";
    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
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
      dynamicFilesFrom = ''
        echo '
          /etc/nixos
          /home/rowan/.ssh
          /home/rowan/org
          /home/rowan/library
          /home/rowan/screenshots
          /home/rowan/memes
          /home/rowan/Pictures
          /home/rowan/drawings
          /home/rowan/farm
          /home/rowan/mindmaps
          /home/rowan/backups
          /home/rowan/harvest
          /home/rowan/projects
        '
        docker exec -it --workdir /data wekan-db mongodump > /dev/null 2>&1
        docker cp wekan-db:/data/dump /home/rowan/backups/wekan/
        echo /home/rowan/backups/wekan
      '';
      repository = "b2:restic-backups-yoga-260-keenbean";
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

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "20.03"; # Did you read the comment?
}

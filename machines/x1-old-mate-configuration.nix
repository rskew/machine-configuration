# Laptop config

# Steps to reproduce laptop state:
# - this config
# - clone github.com/rskew/dotfiles into ~/
# - clone github.com/rskew/bashscripties to ~/scripts
# - add password files to /etc/nixos/secrets/
#   - restic-password for this machine's restic backup repository
#   - restic-b2-appkey.env with B2_ACCOUNT_ID and B2_ACCOUNT_KEY

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

  # Run multiple tailscale daemons using multiple copies of
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/tailscale.nix
  # but giving them differnet socket folders, state folders, and ports.
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
in

{
  imports =
    [ # Include the results of the hardware scan.
      ../hardware-configuration.nix
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
    # For enableAllFirmware
    allowUnfree = true;

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
    unstable.nixops
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
  ];

  virtualisation.docker.enable = true;
  virtualisation.docker.enableOnBoot = true;
  # TODO configure docker services that should run on boot
  # - knowwhat

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

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    authorizedKeysFiles = ["/home/rowan/.ssh/id_rsa.pub"];
    passwordAuthentication = false;
    permitRootLogin = "no";
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [
    #80 # wekan, exposed by docker anyway
    #8085 # knowwhat site
    #8086 # knowwhat ws
    19999 # netdata
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

  services.printing.enable = true;

  services.netdata.enable = true;

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
  };

  nix.trustedUsers = [ "root" "rowan" ];

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
      dynamicFilesFrom = ''
        echo "
          /etc/nixos
          /home/rowan/.ssh
          /home/rowan/mindmaps
          /home/rowan/projects/knowwhat
          /home/rowan/projects/purescript-functorial-data-migration-core
          /home/rowan/projects/purescript-halogen-svg
          /home/rowan/projects/purescript-knuth-bendix
          /home/rowan/projects/purescript-string-rewriting
          /home/rowan/screenshots
          /home/rowan/memes
          /home/rowan/Pictures
          /home/rowan/backups
        "
        docker exec -it --workdir /data wekan-db mongodump > /dev/null 2>&1
        docker cp wekan-db:/data/dump /home/rowan/backups/wekan/
        echo /home/rowan/backups/wekan
      '';
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

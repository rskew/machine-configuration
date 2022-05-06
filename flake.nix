# Steps to reproduce laptop state:
# - setup encrypted hard drive
#   - boot nixos live usb
#   - parted /dev/nvme0n1 -- mklabel gpt
#   - parted /dev/nvme0n1 -- mkpart primary fat32 0% 512MiB
#   - parted /dev/nvme0n1 -- mkpart primary 512MiB 100%
#   - parted /dev/nvme0n1 -- set 1 esp on
#   - parted /dev/nvme0n1 -- name 1 boot
#   - parted /dev/nvme0n1 -- set 2 lvm on
#   - parted /dev/nvme0n1 -- name 2 root
#   - fdisk /dev/vda -l # show partition table
#   - cryptsetup luksFormat /dev/disk/by-partlabel/root # here you create passphrase
#   - cryptsetup luksOpen /dev/disk/by-partlabel/root root
#   - lvmdiskscan # show volumes and partitions
#   - pvcreate /dev/mapper/root
#   - vgcreate vg /dev/mapper/root
#   - lvcreate -L 8G -n swap vg
#   - lvcreate -l '100%FREE' -n root vg
#   - lvdisplay # show volumes and partitions created
#   - mkfs.fat -F 32 -n boot /dev/disk/by-partlabel/boot
#   - mkfs.ext4 -L root /dev/vg/root
#   - mkswap -L swap /dev/vg/swap
#   - mount /dev/disk/by-label/root /mnt
#   - mkdir -p /mnt/boot
#   - mount /dev/disk/by-label/boot /mnt/boot
#   - swapon /dev/vg/swap
#   - swapon -s
# - install laptop config
#   - copy /mnt/home/rowan/.ssh from backup
#   - nix-shell -p git nixFlakes
#   - git clone git@github.com:rskew/machine-configuration /mnt/home/users/rowan/machine-configuration
#   - nixos-install --root /mnt --flake /mnt/home/rowan/machine-configuration#rowan-p14
# - reboot.
#   - log in to root, set user password, log out, log in as user
#   - subsequent rebuilds via:
#     nixos-rebuild --use-remote-sudo switch --flake /root/machine-configuration#rowan-p14
# - enable command-not-found on terminal
#   - sudo nix-channel --add https://nixos.org/channels/nixos-unstable nixos
#   - sudo nix-channel --update
# - install doom emacs
#   - git clone https://github.com/hlissner/doom-emacs ~/.emacs.d
#   - .emacs.d/bin/doom install
# - setup firefox
#   - log in to firefox to get passwords and extensions, and load tabs from simple tab group backups
#   - in about:config set ui.key.menuAccessKeyFocuses to false to disable showing menu when pressing alt (xmonad mod key)
#   - in about:config set devPixelsPerPx to 2 to embiggen UI for hi-res screen
# - to enable backups, add password files to /home/rowan/secrets/
#   - restic-password for this machine's restic backup repository
#   - restic-b2-appkey.env with B2_ACCOUNT_ID and B2_ACCOUNT_KEY

{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-21.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-unstable";
    #kmonad.url = "github:kmonad/kmonad?dir=nix";
    kmonad.url = "github:rskew/kmonad?dir=nix";
    harvest-front-page = {url = "github:rskew/harvest-front-page"; flake = false;};
  };
  outputs =
    { self, nixpkgs, nixpkgs-unstable, home-manager, kmonad, harvest-front-page }:
    let
      pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
      };
      unstable = import nixpkgs-unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
      };
      pythonEnv = pkgs.python39.withPackages(ps: with ps; [
        pandas
        matplotlib
        seaborn
        pyyaml
      ]);
      staticFileServerModule =
        { serverRoot, domain, enableACME ? true, ACMEEmail, forceSSL ? true, ... }:
        {
          services.nginx.enable = true;
          services.nginx.virtualHosts.${domain} = {
            root = serverRoot; enableACME = enableACME; forceSSL = forceSSL;
          };
          security.acme.email = if enableACME then ACMEEmail else null;
          security.acme.acceptTerms = if enableACME then true else false;
        };
    in
    {
      nixosConfigurations.mammoth3 =
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {inherit pkgs unstable;};
          modules = [
            (staticFileServerModule {
              serverRoot = harvest-front-page;
              domain = "castlemaineharvest.com.au";
              enableACME = true; ACMEEmail = "rowan.skewes@gmail.com"; forceSSL = true;
            })
            (staticFileServerModule {
              serverRoot = harvest-front-page;
              domain = "www.castlemaineharvest.com.au";
              enableACME = true; ACMEEmail = "rowan.skewes@gmail.com"; forceSSL = true;
            })
            ({config, pkgs, unstable, modulesPath, ...}: {
              imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
              boot.loader.grub.device = "/dev/vda";
              boot.initrd.kernelModules = [ "nvme" ];
              fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
              networking = {
                nameservers = [
                  "103.236.163.3"
                  "103.236.162.12"
                  "8.8.8.8"
                ];
                defaultGateway = "45.124.52.1";
                defaultGateway6 = "";
                dhcpcd.enable = false;
                usePredictableInterfaceNames = pkgs.lib.mkForce false;
                interfaces = {
                  eth0 = {
                    ipv4.addresses = [
                      { address="45.124.52.135"; prefixLength=24; }
                    ];
                    ipv6.addresses = [
                      { address="fe80::216:3eff:fee0:82ed"; prefixLength=64; }
                    ];
                    ipv4.routes = [ { address = "45.124.52.1"; prefixLength = 32; } ];
                  };
                };
              };
              services.udev.extraRules = ''
                ATTR{address}=="00:16:3e:e0:82:ed", NAME="eth0"

              '';

              boot.cleanTmpDir = true;
              zramSwap.enable = true;
              services.openssh.enable = true;
              users.users.root.openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMP6vikXvdj0wt9/WFCceeOPwimT1LqQcEItLXPTq7ye rowan@rowan-yoga-260-keenbean"
              ];

              nix = {
                package = pkgs.nixFlakes;
                extraOptions = ''
                  experimental-features = nix-command flakes
                '';
              };

              users.users.rowan = {
                isNormalUser = true;
                extraGroups = [ "wheel" "docker" ];
                shell = pkgs.fish;
                openssh.authorizedKeys.keys = [
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMP6vikXvdj0wt9/WFCceeOPwimT1LqQcEItLXPTq7ye rowan@rowan-yoga-260-keenbean"
                ];
              };
              networking.hostName = "rowan-mammoth3";
              networking.firewall.allowedTCPPorts = [ 80 443 ];
            })
            home-manager.nixosModules.home-manager
            ({pkgs, unstable, ...}: {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.rowan = {config, ...}: {
                programs.home-manager.enable = true;

                programs.fish = import ./fish.nix { inherit pkgs; remote = true; };

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

                home.packages = with pkgs; [
                  fzf # for reverse history search in fish shell
                  wget
                  bat
                  git
                  tree
                  rxvt_unicode
                  zip
                  unzip
                  nmap
                  gnupg
                  sl
                  htop
                  file
                  iotop
                  jq
                  rclone
                  restic
                  pythonEnv
                ];
              };
            })
          ];
        };
      nixosConfigurations.rowan-p14 =
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {inherit pkgs unstable;};
          modules = [
            ({config, pkgs, unstable, ...}: {
              imports =
                [ # Include the results of the hardware scan.
                  ./machines/p14-hardware-configuration.nix
                ];

              boot.initrd.luks.devices = {
                root = {
                  device = "/dev/nvme0n1p2";
                  preLVM = true;
                };
              };
              # Use the systemd-boot EFI boot loader.
              boot.loader.efi.canTouchEfiVariables = true;
              #boot.kernelPackages = pkgs.linuxPackages_5_17;
              boot.loader.grub = {
                enable = true;
                version = 2;
                efiSupport = true;
                enableCryptodisk = true;
                device = "nodev";
              };

              nix = {
                package = pkgs.nixFlakes;
                extraOptions = ''
                  experimental-features = nix-command flakes
                '';
              };

              networking.hostName = "rowan-p14";
              networking.networkmanager.enable = true;
              networking.firewall.allowedTCPPorts = [
                19000 # expo
                19002 # expo
                8080 # hasura
                8089 # hasura
                8000
              ];

              time.timeZone = "Australia/Melbourne";

              # The global useDHCP flag is deprecated, therefore explicitly set to false here.
              # Per-interface useDHCP will be mandatory in the future, so this generated config
              # replicates the default behaviour.
              networking.useDHCP = false;
              networking.interfaces.enp0s31f6.useDHCP = true;
              networking.interfaces.wlp0s20f3.useDHCP = true;

              # Select internationalisation properties.
              i18n.defaultLocale = "en_AU.UTF-8";
              fonts.fonts = with pkgs; [ source-code-pro ];

              programs.gnupg.agent = { enable = true; enableSSHSupport = true; };

              services.printing.enable = true;
              services.printing.drivers = [ pkgs.hplip ];

              virtualisation.docker.enable = true;

              environment.systemPackages = with pkgs; [
                wget
                bat
                unstable.emacs
                git
                tree
                unstable.picom-next
                xlibs.xev
                xlibs.xinput
                xlibs.xmessage
                rxvt_unicode
                firefox
                i3lock
                trayer
                networkmanagerapplet
                vlc
                unstable.haskellPackages.xmobar
                pavucontrol
                pinta
                zip
                unzip
                nmap
                gnupg
                xorg.xdpyinfo
                awscli
                sl
                htop
                hunspell
                chromium
                file
                patchelf
                bashmount
                filelight
                iotop
                docker
                docker_compose
                jq
                openvpn
                glxinfo
                qbittorrent
                libreoffice
                pulsemixer
                brightnessctl
                rclone
                restic
                direnv
                unstable.xournalpp
                unstable.signal-desktop
                simplescreenrecorder
                libnotify
                notify-osd
                pythonEnv
                ripgrep # for project-wide search in emacs
                imagemagick # for screenshots via the 'import' command
                unstable.tailscale # for the tailscale CLI
                rofi # launcher
                ## work talk
                unstable.slack
                unstable.teams
                unstable.zoom-us
                ##
                (pkgs.writeShellScriptBin "nvidia-offload" ''
                   export __NV_PRIME_RENDER_OFFLOAD=1
                   export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
                   export __GLX_VENDOR_LIBRARY_NAME=nvidia
                   export __VK_LAYER_NV_optimus=NVIDIA_only
                   exec -a "$0" "$@"
                 '')
              ];

              hardware.pulseaudio = {
                enable = true;
                package = pkgs.pulseaudioFull;
                extraModules = [ pkgs.pulseaudio-modules-bt ];
              };

              hardware.bluetooth.enable = true;
              services.blueman.enable = true;

              # Bluetooth keyboard config
              # Kmonad services are configured via the NixOS module at the bottom of the flake
              services.udev.extraRules = ''
                ATTRS{name}=="TEX-BLE-KB-1 Keyboard", SYMLINK+="tex-kbd"
                ATTRS{name}=="TEX-BLE-KB-1 Keyboard", SUBSYSTEM=="input", ACTION=="add", RUN+="${pkgs.systemd}/bin/systemctl start kmonad-tex-config.service"
                ATTRS{name}=="TEX-BLE-KB-1 Keyboard", SUBSYSTEM=="input", ACTION=="remove", RUN+="${pkgs.systemd}/bin/systemctl stop kmonad-tex-config.service"
              '';
              environment.etc."kmonad/config.kbd".source = pkgs.substitute {
                name = "config.kbd";
                src = ./dotfiles/.config/kmonad/base.kbd;
                replacements = [ "--replace" "keyboard-device" "/dev/input/by-path/platform-i8042-serio-0-event-kbd" ];
              };
              environment.etc."kmonad/tex-config.kbd".source = pkgs.substitute {
                name = "tex-config.kbd";
                src = ./dotfiles/.config/kmonad/base.kbd;
                # /dev/tex-kbd is created by the SYMLINK command in the udev rule above
                replacements = [ "--replace" "keyboard-device" "/dev/tex-kbd" ];
              };

              # Comment these lines to disable gpu
              services.xserver.videoDrivers = [ "nvidia" ];
              hardware.nvidia.prime.intelBusId = "PCI:0:2:0";
              hardware.nvidia.prime.nvidiaBusId = "PCI:1:0:0";
              hardware.nvidia.prime.offload.enable = true;
              hardware.opengl.enable = true;

              services.logind.lidSwitchDocked = "suspend";

              services.xserver = {
                enable = true;
                layout = "us";
                # Enable touchpad support.
                libinput = {
                  enable = true;
                  touchpad = {
                    accelSpeed = "1";
                    naturalScrolling = false;
                  };
                  mouse.scrollMethod = "button";
                  mouse.scrollButton = 2;
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
                displayManager.sessionCommands = with pkgs; lib.mkAfter ''
                  /home/rowan/machine-configuration/scripts/setup_external_monitor.sh
                  ${pkgs.xorg.xrdb}/bin/xrdb -merge /home/rowan/.Xresources
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
                         --height 40 \
                         --monitor "primary" &
                  exec nm-applet &
                  exec blueman-applet &
                  ${pkgs.feh}/bin/feh --bg-scale ~/Pictures/jupyter_near_north_pole.jpg &
                  ${unstable.picom-next}/bin/picom --experimental-backends &
                  ## Synchronise PRIMARY and CLIPBOARD
                  ${autocutsel}/bin/autocutsel -fork -selection CLIPBOARD
                  ${autocutsel}/bin/autocutsel -fork -selection PRIMARY
                  ##
                  ${xautolock}/bin/xautolock -time 10 -locker /home/rowan/machine-configuration/scripts/lock.sh -corners 00-0 &
                '';
              };

              users.users.rowan = {
                isNormalUser = true;
                extraGroups = [ "wheel" "docker" ];
                shell = pkgs.fish;
              };
              # This is required for lightdm to prefill username on login
              programs.fish.enable = true;

              services.redshift = {
                enable = true;
              };
              # Used by redshift
              location = {
                # Melbourne
                latitude = -37.8136;
                longitude = 144.9631;
              };

              systemd.services.lockScreenBeforeSleep = {
                description = "Lock screen before sleep";
                wantedBy = [ "sleep.target" ];
                before = [ "sleep.target" ];
                path = [ pkgs.i3lock ];
                serviceConfig = {
                  Environment = "DISPLAY=:0";
                  User = "rowan";
                };
                script = ''
                  /home/rowan/machine-configuration/scripts/lock.sh
                '';
                serviceConfig.Type = "forking";
              };

              # Initialise rclone for working with backups on backblaze b2
              # - copy rclone.conf containing credentials for backblaze b2 from gdrive to ~/.config/rclone/rclone.conf
              # - copy restic-b2-appkey.env containing credentials for backblaze b2 from gdrive to ~/secrets/restic-b2-appkey.env
              # - create ~/secrets/restic-password containing the plaintext password for the restic repository
              # Creating backup repository
              # - rclone mkdir b2:restic-backups-rowan-p14
              # - source secrets/restic-b2-appkey.env
              # - restic init --repo b2:restic-backups-rowan-p14 --password-file ~/secrets/restic-password
              # Restoring backups:
              # - get snapshot ID to restore (if not using 'latest') via `rclone lsl b2:restic-backups-rowan-p14/snapshots | awk 's/^[ ]*//' | cut -d' ' --complement -f1  | sort -r | head`
              # - source ~/secrets/restic-b2-appkey.env
              # - restic -r <repo> -p /home/rowan/secrets/restic-password restore <snapshot> --target <dir>
              # e.g. `sudo -E restic -r b2:restic-backups-rowan-p14 -p /home/rowan/secrets/restic-password restore latest --target ~/restored-backups/2022-04-10`
              services.restic.backups = {
                remotebackup = {
                  dynamicFilesFrom = ''
                    echo '
                      /home/rowan/.ssh
                      /home/rowan/org
                      /home/rowan/library
                      /home/rowan/screenshots
                      /home/rowan/memes
                      /home/rowan/Pictures
                      /home/rowan/drawings
                      /home/rowan/farm
                      /home/rowan/harvest
                      /home/rowan/projects
                      /home/rowan/Downloads/STG-backups*
                    '
                  '';
                  repository = "b2:restic-backups-rowan-p14";
                  passwordFile = "/home/rowan/secrets/restic-password-p14";
                  environmentFile = "/home/rowan/secrets/restic-b2-appkey.env";
                  timerConfig = {
                    OnCalendar = "daily";
                  };
                  initialize = true;
                };
              };

              system.stateVersion = "21.11"; # Did you read the comment?
            })

            home-manager.nixosModules.home-manager
            ({pkgs, unstable, ...}: {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.rowan = {config, ...}: {
                programs.home-manager.enable = true;

                programs.fish = import ./fish.nix { inherit pkgs; };

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

                gtk = {
                  enable = true;
                  font.name = "Sans 20"; # make firefox font big for hi-res monitor
                  cursorTheme = {
                    name = "Adwaita";
                    size = 40; # make cursor big for hi-res monitor
                  };
                };

                home.packages = with pkgs; [
                  gnome3.dconf # Required for gtk3 configuration
                  fzf # for reverse history search in fish shell
                ];

                # dotfiles
                home.file.".xmonad/xmonad.hs".source   = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.xmonad/xmonad.hs";
                home.file.".xmobarrc".source           = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.xmobarrc";
                home.file.".Xresources".source         = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.Xresources";
                home.file.".doom.d/config.el".source   = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.doom.d/config.el";
                home.file.".doom.d/init.el".source     = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.doom.d/init.el";
                home.file.".doom.d/packages.el".source = config.lib.file.mkOutOfStoreSymlink "/home/rowan/machine-configuration/dotfiles/.doom.d/packages.el";
              };
            })
            kmonad.nixosModule ({...}: {
              services.kmonad = {
                enable = true;
                configfiles = [
                  "/etc/kmonad/config.kbd"
                  "/etc/kmonad/tex-config.kbd"
                ];
                package = kmonad.packages.x86_64-linux.kmonad;
                make-group = false;
              };
            })
          ];
      };
    };
}

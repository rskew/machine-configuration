{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-22.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    kmonad.url = "github:rskew/kmonad?dir=nix";
    harvest-front-page = { url = "github:rskew/harvest-front-page"; flake = false; };
    harvest-admin-app.url = "git+ssh://git@github.com/rskew/greengrocer-admin-app.git";
    coolroom-monitor.url = "git+ssh://git@github.com/rskew/coolroom-monitor.git";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    autofarm.url = "github:rskew/autofarm";
    #autofarm.url = "/home/rowan/autofarm";
  };
  outputs =
    { self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      kmonad,
      harvest-front-page,
      harvest-admin-app,
      coolroom-monitor,
      agenix,
      autofarm,
    }:
    let
      pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
      };
      unstable = import nixpkgs-unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
      };
      jumpBoxIp = "45.124.54.206";
      jumpBoxKnownHostsLine = "45.124.54.206 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBBiOw+sB106FeeF6wp52n5FQt3s+8zOmCRZHcvhUsq3";
      vpsManagementPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMP6vikXvdj0wt9/WFCceeOPwimT1LqQcEItLXPTq7ye rowan@rowan-yoga-260-keenbean"; # id_ed25519_mammoth.pub
      pubkeyToDeployToVps = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINyNsCdnk/Q9H9OWakN0llCHbgb4RTB0f2na54XEy6FW rowan@rowan-p14"; # id_to_deploy_to_servers1.pub
      shedPowerMonitorDeviceSymlink = "vedirect-usb";
      shedPowerMonitor = import ./applications/shed-power-monitor { inherit pkgs; device_path = "/dev/${shedPowerMonitorDeviceSymlink}"; };
    in
    rec {

      nixosConfigurations.vps1 =
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {inherit pkgs unstable;};
          modules = [
            (import ./machines/vps1/hardware-configuration.nix)
            (import ./machines/vps1/networking.nix)

            ({
              services.nginx.enable = true;
              services.nginx.virtualHosts = {
                "castlemaineharvest.com.au" = {
                  root = harvest-front-page;
                  enableACME = true;
                  forceSSL = true;
                  serverAliases = ["www.castlemaineharvest.com.au"];
                };
                "coolroom.castlemaineharvest.com.au" = {
                  locations."/".proxyPass = "http://127.0.0.1:3000/";
                  enableACME = true;
                  forceSSL = true;
                  serverAliases = ["www.coolroom.castlemaineharvest.com.au"];
                };
                "coolroom-sensor.castlemaineharvest.com.au" = {
                  locations."/".proxyPass = "http://127.0.0.1:8086/";
                  enableACME = true;
                  forceSSL = true;
                };
                "objectionable.farm" = {
                  locations."/".proxyPass = "http://127.0.0.1:3001/";
                  enableACME = true;
                  acmeRoot = null;
                  forceSSL = true;
                  serverAliases = ["top-tank.objectionable.farm"];
                };
              };
              services.nginx.recommendedProxySettings = true;
              security.acme.defaults.email = "rowan.skewes@gmail.com";
              security.acme.acceptTerms = true;
              networking.firewall.allowedTCPPorts = [ 443 ];
            })

            # WARNING: This configuration is insecure for fresh deployments.
            # You must activate influxdb-and-grafana **without exposing publicly** (i.e. comment out the nginx config above)
            # then set the admin password for influxdb and for grafana
            coolroom-monitor.nixosModules.influxdb-and-grafana
            ({...}: {
              services.influxdb.dataDir = "/home/rowan/.influxdb-data";
              services.influxdb.user = "rowan";
              services.grafana.settings = {};
            })

            ({pkgs, config, ...}: {
              security.acme = {
                acceptTerms = true;
                certs."objectionable.farm" = {
                  email = "certs+rowan.skewes@gmail.com";
                  group = "nginx";
                  postRun = ''
                    cp ${config.security.acme.certs."objectionable.farm".directory}/fullchain.pem /postgres-fullchain.pem
                    # The cert must be owned by postgres user
                    chown postgres:postgres /postgres-fullchain.pem
                    # Need to set to 600 otherwise get SSL error code 2147483661
                    chmod 600 /postgres-fullchain.pem
                    cp ${config.security.acme.certs."objectionable.farm".directory}/key.pem /postgres-key.pem
                    chown postgres:postgres /postgres-key.pem
                    chmod 600 /postgres-key.pem
                  '';
                  dnsProvider = "namecheap";
                  dnsPropagationCheck = false;
                  credentialsFile = config.age.secrets.namecheap-api-credentials.path;
                };
              };
              services.postgresql = {
                enable = true;
                package = pkgs.postgresql;
                extraPlugins = [ pkgs.postgresqlPackages.postgis ];
                port = 5432;
                initdbArgs = ["--pwfile=${config.age.secrets.farmdb-pgpassword.path}"];
                initialScript = pkgs.writeText "initialScript" ''
                  CREATE EXTENSION postgis;
                  CREATE EXTENSION postgis_raster;
                '';
                settings = {
                  ssl = "on";
                  ssl_cert_file = "/postgres-fullchain.pem";
                  ssl_key_file = "/postgres-key.pem";
                  archive_mode = "on";
                  archive_command = "env $(cat ${config.age.secrets.pgbackrest-credentials-env.path}) ${pkgs.pgbackrest}/bin/pgbackrest --stanza=farmdb archive-push %p";
                  archive_timeout = 300;
                };
                enableTCPIP = true; # Listen on 0.0.0.0
                authentication = ''
                  # Force SSL by only having 'hostssl' and no 'host' lines
                  hostssl all all 0.0.0.0/0 md5
                  hostssl all all ::0/0     md5
                '';
              };
              systemd.services.postgresql.requires = [ "acme-finished-objectionable.farm.target" ];
              networking.firewall.allowedTCPPorts = [ 5432 ];
              # TODO make pgbackrest service module
              # TODO put postgres + pgbackrest configuration in autofarm with a few parameters
              # Creating backup repository
              # - cd ~/machine-configuration/secrets
              # - env $(agenix -i ~/.ssh/id_to_deploy_to_servers1 -d b2-credentials.age) \
              #       aws --endpoint-url https://s3.us-west-000.backblazeb2.com s3api create-bucket --bucket farmdb-backup
              # - sudo -u postgres env $(cat /run/agenix/pgbackrest-credentials-env) $(readlink $(which pgbackrest)) --stanza=farmdb --log-level-console=info stanza-create
              # - sudo -u postgres env $(cat /run/agenix/pgbackrest-credentials-env) $(readlink $(which pgbackrest)) --stanza=farmdb --log-level-console=info check
              # - sudo -u postgres env $(cat /run/agenix/pgbackrest-credentials-env) $(readlink $(which pgbackrest)) --stanza=farmdb --log-level-console=info info
              # Take first backup:
              # - sudo -u postgres env $(cat /run/agenix/pgbackrest-credentials-env) $(readlink $(which pgbackrest)) --stanza=farmdb --log-level-console=info --type=full backup
              # Restoring backups:
              # - stop the database
              # - sudo -u postgres env $(cat /run/agenix/pgbackrest-credentials-env) $(readlink $(which pgbackrest)) --stanza=farmdb --log-level-console=detail --delta restore
              # - start the database
              # Restore dev db from backup:
              #   - cd /home/rowan/machine-configuration/secrets
              #   - cat <<EOF > pgbackrest.conf
              #     [farmdb]
              #     pg1-path=/home/rowan/farm/autofarm/db/.db-data
              #     pg1-user=postgres
              #     repo1-retention-full=2
              #     repo1-type=s3
              #     repo1-path=/postgres
              #     repo1-s3-bucket=farmdb-backup
              #     repo1-s3-endpoint=s3.us-west-000.backblazeb2.com
              #     repo1-s3-region=us-west-000
              #     repo1-cipher-type=aes-256-cbc
              #     delta=y
              #     compress-type=zst
              #     compress-level=6
              #     EOF
              #   - env $(agenix -i ~/.ssh/id_rowan2 -d pgbackrest-credentials-env.age) \
              #       pgbackrest \
              #         --config=$PWD/pgbackrest.conf \
              #         --stanza=farmdb \
              #         --delta \
              #         restore
              #   - rm pgbackrest.conf
              environment.etc."pgbackrest/pgbackrest.conf".text = ''
                [farmdb]
                pg1-path=${config.postgresql.datadir}
                pg1-user=postgres
                repo1-retention-full=2
                repo1-type=s3
                repo1-path=/postgres
                repo1-s3-bucket=farmdb-backup
                repo1-s3-endpoint=s3.us-west-000.backblazeb2.com
                repo1-s3-region=us-west-000
                repo1-cipher-type=aes-256-cbc
                # Force a checkpoint to start backup immediately.
                start-fast=y
                # Use delta restore.
                delta=y
                compress-type=zst
                compress-level=6
              '';
              systemd.services.postgres-backup-full = {
                path = [ pkgs.pgbackrest agenix.packages.x86_64-linux.agenix ];
                script = ''
                  if readlink ${config.postgresql.datadir}; then
                    echo Copying postgresql.conf out of nix store so that it can have writable mode, required for restore
                    cp "$(readlink ${config.postgresql.datadir})" ${config.postgresql.datadir}
                    chmod +w ${config.postgresql.datadir}
                  fi
                  env $(cat ${config.age.secrets.pgbackrest-credentials-env.path}) pgbackrest --stanza=farmdb --type=full backup
                '';
                serviceConfig.User = "postgres";
              };
              systemd.timers.postgres-backup-full = {
                partOf      = [ "postgres-backup-full.service" ];
                wantedBy    = [ "timers.target" ];
                timerConfig.OnCalendar = "Wed 2:33 Australia/Melbourne";
              };
              systemd.services.postgres-backup-incr = {
                path = [ pkgs.pgbackrest agenix.packages.x86_64-linux.agenix ];
                script = ''
                  if readlink ${config.postgresql.datadir}; then
                    echo Copying postgresql.conf out of nix store so that it can have writable mode, required for restore
                    cp "$(readlink ${config.postgresql.datadir})" ${config.postgresql.datadir}
                    chmod +w ${config.postgresql.datadir}
                  fi
                  env $(cat ${config.age.secrets.pgbackrest-credentials-env.path}) pgbackrest --stanza=farmdb --type=incr backup
                '';
                serviceConfig.User = "postgres";
              };
              systemd.timers.postgres-backup-incr = {
                partOf      = [ "postgres-backup-incr.service" ];
                wantedBy    = [ "timers.target" ];
                timerConfig.OnCalendar = "Mon,Tue,Thu,Fri,Sat,Sun 2:33 Australia/Melbourne";
              };
            })

            agenix.nixosModules.age
            ({...}: {
              age.secrets.farmdb-pgpassword.file = ./secrets/farmdb-pgpassword.age;
              age.secrets.farmdb-pgpassword.mode = "770";
              age.secrets.farmdb-pgpassword.owner = "postgres";
              age.secrets.farmdb-pgpassword.group = "postgres";
              age.secrets."pgbackrest-credentials-env".file = ./secrets/pgbackrest-credentials-env.age;
              age.secrets."pgbackrest-credentials-env".mode = "440";
              age.secrets."pgbackrest-credentials-env".owner = "postgres";
              age.secrets."pgbackrest-credentials-env".group = "postgres";
              age.secrets.b2-credentials.file = ./secrets/b2-credentials.age;
              age.secrets.namecheap-api-credentials.file = ./secrets/namecheap-api-credentials.age;
              age.identityPaths = [ "/home/rowan/.ssh/id_to_deploy_to_servers1" ];
            })

            ({pkgs, ...}: {
              networking.hostName = "rowan-vps1";

              # Default hardware-configuration has no swap device,
              # causing nixos-rebuilt to crash
              swapDevices = pkgs.lib.mkOverride 5 [
                {
                  device = "/swapfile";
                  size = 3000; # MB
                }
              ];

              # Drop inactive sessions after 1.5 minutes.
              # This prevents stale sessions from stopping clients
              # reconnecting with port forwarding.
              services.openssh.extraConfig = ''
                ClientAliveInterval 30
                ClientAliveCountMax 3
              '';
              # Don't allow inbound ssh connections to forward ports on 0.0.0.0
              services.openssh.gatewayPorts = "no";
              users.users.root.openssh.authorizedKeys.keys = [ vpsManagementPubkey ];

              services.openssh = {
                enable = true;
                passwordAuthentication = false;
                permitRootLogin = "no";
                forwardX11 = false;
              };

              services.journald.extraConfig = "SystemMaxUse=1G";

              users.users.rowan = {
                isNormalUser = true;
                extraGroups = [ "wheel" "docker" "dialout" "postgres" ];
                shell = pkgs.fish;
                openssh.authorizedKeys.keys = [
                  vpsManagementPubkey
                  pubkeyToDeployToVps # Allow other servers to SSH to this server
                ];
              };
              security.sudo.wheelNeedsPassword = false;

              nix.package = pkgs.nixFlakes;
              nix.extraOptions = "experimental-features = nix-command flakes";
              system.stateVersion = "22.05";
            })

            home-manager.nixosModules.home-manager
            ({pkgs, unstable, ...}: {
              home-manager.useGlobalPkgs = true;
              home-manager.users.rowan =
                {config, pkgs, ...}:
                import ./home.nix {inherit config pkgs unstable agenix; isGraphical = false;};
            })
          ];
        };

      nixosConfigurations.shop-server =
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {inherit pkgs unstable;};
          modules = [

            harvest-admin-app.nixosModules.admin-app-services

            coolroom-monitor.nixosModules.coolroom-monitor-relay
            ({config, ...}: {
              services.coolroom-monitor-relay.influxdb-password-file = config.age.secrets."coolroom-monitor-influxdb-password".path;
            })

            agenix.nixosModules.age
            ({...}: {
              age.secrets."coolroom-monitor-influxdb-password".file = ./secrets/coolroom-monitor-influxdb-password.age;
              age.identityPaths = [ "/home/rowan/.ssh/id_to_deploy_to_servers1" ];
            })

            # Forward the port of the register DB to the cloud server
            # so the shop admin app database can connect directly to the
            # register database for keeping prices up-to-date
            (import ./persistent-ssh-tunnel.nix)
            ({...}: {
              services.persistentSSHTunnel = {
                enable = true;
                remoteIp = jumpBoxIp;
                remoteUser = "rowan";
                idFile = "/home/rowan/.ssh/id_to_deploy_to_servers1";
                knownHostsLine = jumpBoxKnownHostsLine;
                remoteForwards = [
                  { localIp = "192.168.0.121"; localPort = 8001; remotePort = 5001; }
                ];
              };
            })

            ({config, pkgs, unstable, ...}: {
              imports =
                [./machines/shop-server-z230-hardware-configuration.nix
                ];

              networking.hostName = "shop-server";

              networking.networkmanager.enable = true;

              # This machine is behind a router NAT
              networking.firewall.allowedTCPPorts = [
                8080 # Hasura
                80 443 # test admin app
                8005
              ];

              virtualisation.docker.enable = true;

              environment.systemPackages = with pkgs; [
                pgcli
                postgresql
              ];

              # Use the systemd-boot EFI boot loader.
              boot.loader.systemd-boot.enable = true;
              boot.loader.efi.canTouchEfiVariables = true;

              # Enable firmware for rtl wireless chip
              nixpkgs.config.allowUnfree = true;
              hardware.enableAllFirmware = true;

              # Set the eno1 interface to use the 192.168.0.* subnet so it can talk to the registers
              # and add static routes to the registers
              networking.interfaces.eno1.ipv4 = {
                addresses = [ {
                  address = "192.168.0.60";
                  prefixLength = 24;
                } ];
                routes = [
                  { address = "192.168.0.121"; prefixLength = 32; }
                  { address = "192.168.0.122"; prefixLength = 32; }
                ];
              };
              # But remove all other routes via ethernet so it doesn't mess up using the wifi for internet
              networking.localCommands = ''
                ip route del 192.168.0.0/24 dev eno1 proto kernel scope link src 192.168.0.60
              '';

              # The global useDHCP flag is deprecated, therefore explicitly set to false here.
              # Per-interface useDHCP will be mandatory in the future, so this generated config
              # replicates the default behaviour.
              networking.useDHCP = false;
              networking.interfaces.eno1.useDHCP = true;
              networking.interfaces.wlp0s20u4.useDHCP = true;

              # Select internationalisation properties.
              i18n.defaultLocale = "en_AU.UTF-8";

              # Set your time zone.
              time.timeZone = "Australia/Melbourne";

              services.openssh = {
                enable = true;
                passwordAuthentication = false;
                permitRootLogin = "no";
                forwardX11 = false;
              };

              users.users.rowan = {
                isNormalUser = true;
                extraGroups = [
                  "wheel"  # Enable ‘sudo’ for the user.
                  "docker"
                ];
                openssh.authorizedKeys.keys = [ vpsManagementPubkey ];
                shell = pkgs.fish;
              };

              nix.package = pkgs.nixFlakes;
              nix.extraOptions = "experimental-features = nix-command flakes";
              system.stateVersion = "20.03"; # Did you read the comment?
            })

            home-manager.nixosModules.home-manager
            ({pkgs, unstable, lib, ...}: {
              home-manager.useGlobalPkgs = true;
              home-manager.users.rowan =
                {config, pkgs, ...}:
                import ./home.nix {inherit config pkgs unstable agenix; isGraphical = false;};
            })
          ];
        };

      packages.x86_64-linux.shedPowerMonitor = shedPowerMonitor.package;
      devShells.x86_64-linux.shedPowerMonitor = pkgs.mkShell {
        buildInputs = [ pkgs.nodejs pkgs.nodePackages.node2nix ];
        NODE_PATH = shedPowerMonitor.NODE_PATH;
        shellHook = "cd applications/shed-power-monitor";
      };

      nixosConfigurations.farm-server =
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {inherit pkgs unstable;};
          modules = [

            autofarm.nixosModule
            ({config, ...}: {
              services.autofarm = {
                deviceMonitorDeviceListenerPort = 9222;
                ecronServerEcrontab = "/home/rowan/.autofarm/ecrontab";
                frontendServerBasicAuthCredentialsFile = config.age.secrets."autofarm-frontend-server-basic-auth-credentials".path;
                deviceMonitorInfluxdbPort = 8086;
              };
            })
            # FTDI USB thingo as GPIO for flicking relays that control irrigation solenoids
            ({...}: {
              services.udev.extraRules = ''
                SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6001", GROUP="dialout", MODE="0664", SYMLINK+="ftdi-thingo"
              '';
            })

            agenix.nixosModules.age
            ({...}: {
              age.secrets."autofarm-frontend-server-basic-auth-credentials".file = ./secrets/autofarm-frontend-server-basic-auth-credentials.age;
              age.identityPaths = [ "/home/rowan/.ssh/id_to_deploy_to_servers1" ];
            })

            shedPowerMonitor.module
            ({...}: {
              services.udev.extraRules = ''
                SUBSYSTEM=="tty", ATTRS{idProduct}=="6015", ATTRS{idVendor}=="0403", ATTRS{serial}=="VE6INUFY", GROUP="dialout", MODE="0664", SYMLINK+="${shedPowerMonitorDeviceSymlink}"
              '';
            })

            (import ./persistent-ssh-tunnel.nix)
            ({...}: {
              services.persistentSSHTunnel = {
                enable = true;
                remoteIp = jumpBoxIp;
                remoteUser = "rowan";
                idFile = "/home/rowan/.ssh/id_to_deploy_to_servers1";
                knownHostsLine = jumpBoxKnownHostsLine;
                remoteForwards = [
                  { localPort = 22; remotePort = 7722; } # SSH
                  { localPort = 3000; remotePort = 3001; } # Grafana
                ];
              };
            })

            ({config, pkgs, unstable, ...}: {
              imports =
                [./machines/farm-server-digital-hardware-configuration.nix
                ];
              networking.hostName = "farm-server-digital";
              networking.networkmanager.enable = true;
              networking.useDHCP = false;
              networking.interfaces.enp3s0.useDHCP = true;

              # Use the systemd-boot EFI boot loader.
              boot.loader.systemd-boot.enable = true;
              boot.loader.efi.canTouchEfiVariables = true;

              # Select internationalisation properties.
              i18n.defaultLocale = "en_AU.UTF-8";
              # Set your time zone.
              time.timeZone = "Australia/Melbourne";

              services.openssh = {
                enable = true;
                passwordAuthentication = false;
                permitRootLogin = "no";
                forwardX11 = false;
              };

              users.users.rowan = {
                isNormalUser = true;
                extraGroups = [
                  "wheel"  # Enable ‘sudo’ for the user.
                  "docker"
                  "usb" "dialout" "uucp"
                ];
                openssh.authorizedKeys.keys = [ vpsManagementPubkey ];
                shell = pkgs.fish;
              };

              nix.package = pkgs.nixFlakes;
              nix.extraOptions = "experimental-features = nix-command flakes";
              system.stateVersion = "20.03"; # Did you read the comment?
            })

            home-manager.nixosModules.home-manager
            ({pkgs, unstable, lib, ...}: {
              home-manager.useGlobalPkgs = true;
              home-manager.users.rowan =
                {config, pkgs, ...}:
                import ./home.nix {inherit config pkgs unstable agenix; isGraphical = false;};
            })
          ];
        };

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
      nixosConfigurations.rowan-p14 =
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {inherit pkgs unstable;};
          modules = [

            agenix.nixosModules.age
            ({...}: {
              age.secrets."b2-credentials".file = ./secrets/b2-credentials.age;
              age.secrets."restic-password".file = ./secrets/restic-password.age;
              age.identityPaths = [ "/home/rowan/.ssh/id_rowan2" ];
            })

            home-manager.nixosModules.home-manager
            ({pkgs, unstable, lib, ...}: {
              home-manager.useGlobalPkgs = true;
              home-manager.users.rowan =
                {config, pkgs, ...}:
                import ./home.nix {inherit config pkgs unstable agenix; isGraphical = true;};
            })

            kmonad.nixosModule
            # Bluetooth keyboard config
            ({lib, ...}: {
              services.kmonad = {
                enable = true;
                configfiles = [
                  "/etc/kmonad/config.kbd"
                  "/etc/kmonad/tex-config.kbd"
                  "/etc/kmonad/mac-kbd-config.kbd"
                ];
                package = kmonad.packages.x86_64-linux.kmonad;
                make-group = false;
              };
              environment.etc."kmonad/config.kbd".source = pkgs.substitute {
                name = "config.kbd";
                src = ./dotfiles/.config/kmonad/base.kbd;
                replacements = [ "--replace" "keyboard-device" "/dev/input/by-path/platform-i8042-serio-0-event-kbd" ]; # Built-in keyboard
              };
              environment.etc."kmonad/tex-config.kbd".source = pkgs.substitute {
                name = "tex-config.kbd";
                src = ./dotfiles/.config/kmonad/base.kbd;
                # /dev/tex-kbd is created by the SYMLINK command in the udev rule below
                replacements = [ "--replace" "keyboard-device" "/dev/tex-kbd" ];
              };
              environment.etc."kmonad/mac-kbd-config.kbd".source = pkgs.substitute {
                name = "mac-kbd-config.kbd";
                src = ./dotfiles/.config/kmonad/mac-kbd-base.kbd;
                replacements = [ "--replace" "keyboard-device" "/dev/mac-kbd" ]; # Usb mac keyboard
              };
              services.udev.extraRules = ''
                ATTRS{name}=="TEX-BLE-KB-1 Keyboard", SYMLINK+="tex-kbd"
                ATTRS{name}=="TEX-BLE-KB-1 Keyboard", SUBSYSTEM=="input", ACTION=="add", RUN+="${pkgs.systemd}/bin/systemctl start kmonad-tex-config.service"
                ATTRS{name}=="TEX-BLE-KB-1 Keyboard", SUBSYSTEM=="input", ACTION=="remove", RUN+="${pkgs.systemd}/bin/systemctl stop kmonad-tex-config.service"
                SUBSYSTEM=="input", ATTRS{idProduct}=="024f", ATTRS{idVendor}=="05ac", SYMLINK+="mac-kbd"
                SUBSYSTEM=="input", ATTRS{idProduct}=="024f", ATTRS{idVendor}=="05ac", ACTION="add", RUN+="${pkgs.systemd}/bin/systemctl start kmonad-mac-kbd-config.service"
                SUBSYSTEM=="input", ATTRS{idProduct}=="024f", ATTRS{idVendor}=="05ac", ACTION="remove", RUN+="${pkgs.systemd}/bin/systemctl stop kmonad-mac-kbd-config.service"
              '';
              # Disable the unit for external keyboards so they don't start automatically.
              # The udev rules will start the unit for the bluetooth keyboard when the keyboard connects.
              # When enabled, sometimes these service use 100% of all CPU cores on boot :/
              systemd.services.kmonad-tex-config.wantedBy = lib.mkForce [];
              systemd.services.kmonad-mac-kbd-config.wantedBy = lib.mkForce [];
            })

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
              boot.loader.grub = {
                enable = true;
                version = 2;
                efiSupport = true;
                enableCryptodisk = true;
                device = "nodev";
              };

              networking.hostName = "rowan-p14";
              networking.networkmanager.enable = true;
              networking.firewall.allowedTCPPorts = [
                2001 # notification server
                9222 # autofarm device_monitor dev
                8181 # shop admin app dev
              ];

              services.tailscale.enable = true;

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
                gping
                rclone
                restic
                unstable.picom-next
                xorg.xev
                xorg.xinput
                xorg.xmessage
                unstable.firefox
                i3lock
                trayer
                networkmanagerapplet
                vlc
                unstable.haskellPackages.xmobar
                pavucontrol
                pinta
                gnupg
                awscli
                hunspell
                chromium
                bashmount
                filelight
                docker
                docker-compose
                openvpn
                glxinfo
                qbittorrent
                libreoffice
                pulsemixer
                pulseaudio
                alsa-utils
                brightnessctl
                direnv
                unstable.xournalpp
                unstable.signal-desktop
                simplescreenrecorder
                libnotify
                imagemagick # for screenshots via the 'import' command
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
                nix-tree
              ];

              security.rtkit.enable = true;
              services.pipewire = {
                enable = true;
                alsa.enable = true;
                alsa.support32Bit = true;
                pulse.enable = true;
                jack.enable = true;
              };

              hardware.bluetooth.enable = true;
              services.blueman.enable = true;

              # Comment these lines to disable gpu
              #services.xserver.videoDrivers = [ "nvidia" ];
              #hardware.nvidia.prime.intelBusId = "PCI:0:2:0";
              #hardware.nvidia.prime.nvidiaBusId = "PCI:1:0:0";
              #hardware.nvidia.prime.offload.enable = true;
              #hardware.opengl.enable = true;

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
                autoRepeatDelay = 200; # milliseconds
                autoRepeatInterval = 28; # milliseconds
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
                # this used to be .xinitrc
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
                  ${pkgs.feh}/bin/feh --bg-scale ~/Pictures/Jupyter_full_flat.png &
                  ${unstable.picom-next}/bin/picom --experimental-backends &
                  ## Synchronise PRIMARY and CLIPBOARD
                  ${autocutsel}/bin/autocutsel -fork -selection CLIPBOARD
                  ${autocutsel}/bin/autocutsel -fork -selection PRIMARY
                  ##
                  ${xautolock}/bin/xautolock -time 15 -locker /home/rowan/machine-configuration/scripts/lock.sh -corners 00-0 &
                '';
              };

              users.users.rowan = {
                isNormalUser = true;
                extraGroups = [ "wheel" "docker" "dialout" ];
                shell = pkgs.fish;
              };
              # This is required for lightdm to prefill username on login
              programs.fish.enable = true;
              # This is required to use completions that come from
              # installed packages
              programs.fish.vendor.completions.enable = true;

              services.redshift.enable = true;
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
                path = [ pkgs.bash pkgs.i3lock ];
                serviceConfig = {
                  Environment = "DISPLAY=:0";
                  User = "rowan";
                };
                script = ''
                  /home/rowan/machine-configuration/scripts/lock.sh
                '';
                serviceConfig.Type = "forking";
              };

              # Backups
              # Creating backup repository
              # - cd ~/machine-configuration/secrets
              # - env (agenix -i ~/.ssh/id_rowan2 -d b2-credentials.age) RESTIC_PASSWORD=(agenix -i ~/.ssh/id_rowan2 -d restic-password.age) fish
              # - aws --endpoint-url https://s3.us-west-000.backblazeb2.com s3api create-bucket --bucket restic-backups-rowan-p14
              # - restic init --repo s3:https://s3.us-west-000.backblazeb2.com/restic-backups-rowan-p14
              # Restoring backups:
              # - get snapshot ID to restore (if not using 'latest') via:
              #       aws --endpoint-url https://s3.us-west-000.backblazeb2.com s3 ls s3://restic-backups-rowan-p14/snapshots/ | sed 's/^[ ]*//' | cut -d' ' --complement -f1  | sort -r
              # - restic -r <repo> restore <snapshot> --target <dir>
              # e.g. restic -r s3:https://s3.us-west-000.backblazeb2.com/restic-backups-rowan-p14 restore latest --target ~/restored-backups/2022-04-10
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
                  repository = "s3:https://s3.us-west-000.backblazeb2.com/restic-backups-rowan-p14";
                  passwordFile = config.age.secrets.restic-password.path;
                  environmentFile = config.age.secrets.b2-credentials.path;
                  timerConfig = {
                    OnCalendar = "daily";
                  };
                  initialize = true;
                };
              };

              nix.package = pkgs.nixFlakes;
              nix.extraOptions = "experimental-features = nix-command flakes";
              system.stateVersion = "21.11"; # Did you read the comment?
            })
          ];
      };
    };
}

{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-unstable";
    kmonad.url = "github:kmonad/kmonad?dir=nix";
    harvest-front-page = { url = "github:rskew/harvest-front-page"; flake = false; };
    harvest-admin-app.url = "git+ssh://git@github.com/rskew/greengrocer-admin-app.git";
    coolroom-monitor.url = "git+ssh://git@github.com/rskew/coolroom-monitor.git";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    autofarm.url = "github:rskew/autofarm";
    notification-listener.url = "git+ssh://git@github.com/rskew/notification-listener";
    meetthecandidatesmtalexander = { url = "github:rskew/meetthecandidatesmtalexander.com.au"; flake = false; };
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
      notification-listener,
      meetthecandidatesmtalexander,
    }:
    let
      pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
      };
      pkgs-old = import nixpkgs {
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

      homeConfigurations.rowan = home-manager.lib.homeManagerConfiguration {
        modules = [ (import ./home.nix) (
          { config, pkgs, ... }: {
            home.username = "rowan";
            home.homeDirectory = "/home/users/rowan";
          }
        ) ];
        extraSpecialArgs = {
          isGraphical = false;
          unstable = unstable;
          agenix = agenix;
        };
      };

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
                "meetthecandidatesmtalexander.com.au" = {
                  root = meetthecandidatesmtalexander;
                  enableACME = true;
                  forceSSL = true;
                  serverAliases = ["www.meetthecandidatesmtalexander.com.au"];
                };
              };
              services.nginx.recommendedProxySettings = true;
              security.acme.defaults.email = "rowan.skewes@gmail.com";
              security.acme.acceptTerms = true;
              networking.firewall.allowedTCPPorts = [ 80 443 ];
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
                package = pkgs.postgresql_14;
                extraPlugins = [ pkgs.postgresql14Packages.postgis ];
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
              # - restore from last backup:
              #   - stop the database
              #   - sudo -u postgres env $(cat /run/agenix/pgbackrest-credentials-env) $(readlink $(which pgbackrest)) --cmd="env $(cat /run/agenix/pgbackrest-credentials-env | tr '\n' ' ') $(readlink $(which pgbackrest))" --stanza=farmdb --log-level-console=detail --delta restore
              #   - start the database
              # - restore from point-in-time:
              #   - sudo -u postgres env $(cat /run/agenix/pgbackrest-credentials-env) $(readlink $(which pgbackrest)) --cmd="env $(cat /run/agenix/pgbackrest-credentials-env | tr '\n' ' ') $(readlink $(which pgbackrest))" --stanza=farmdb --log-level-console=detail --delta --type=time '--target=xxxx-xx-xx xx:xx:xx' restore
              #   - start the database
              #   - run 'SELECT pg_wal_replay_resume();'
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
                pg1-path=${config.services.postgresql.dataDir}
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
                  confpath=${config.services.postgresql.dataDir}/postgresql.conf
                  if readlink "$confpath"; then
                    echo Copying postgresql.conf out of nix store so that it can have writable mode, required for restore
                    cp --remove-destination "$(readlink "$confpath")" "$confpath"
                    chmod +w "$confpath"
                  fi
                  env $(cat ${config.age.secrets.pgbackrest-credentials-env.path}) pgbackrest --stanza=farmdb --type=full backup
                '';
                serviceConfig.User = "postgres";
              };
              systemd.timers.postgres-backup-full = {
                partOf      = [ "postgres-backup-full.service" ];
                wantedBy    = [ "timers.target" ];
                timerConfig.OnCalendar = "*-1,7-1 3:33 Australia/Melbourne";
              };
              systemd.services.postgres-backup-incr = {
                path = [ pkgs.pgbackrest agenix.packages.x86_64-linux.agenix ];
                script = ''
                  confpath=${config.services.postgresql.dataDir}/postgresql.conf
                  if readlink "$confpath"; then
                    echo Copying postgresql.conf out of nix store so that it can have writable mode, required for restore
                    cp --remove-destination "$(readlink "$confpath")" "$confpath"
                    chmod +w "$confpath"
                  fi
                  env $(cat ${config.age.secrets.pgbackrest-credentials-env.path}) pgbackrest --stanza=farmdb --type=incr backup
                '';
                serviceConfig.User = "postgres";
              };
              systemd.timers.postgres-backup-incr = {
                partOf      = [ "postgres-backup-incr.service" ];
                wantedBy    = [ "timers.target" ];
                timerConfig.OnCalendar = "Wed 2:33 Australia/Melbourne";
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

              users.users.root.openssh.authorizedKeys.keys = [ vpsManagementPubkey ];

              services.openssh = {
                enable = true;
                settings = {
                  PasswordAuthentication = false;
                  PermitRootLogin = "no";
                  X11Forwarding = false;
                  # Don't allow inbound ssh connections to forward ports on 0.0.0.0
                  GatewayPorts = "no";
                };
                # Drop inactive sessions after 1.5 minutes.
                # This prevents stale sessions from stopping clients
                # reconnecting with port forwarding.
                extraConfig = ''
                  ClientAliveInterval 30
                  ClientAliveCountMax 3
                '';
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
              programs.fish.enable = true;

              nix.package = pkgs.nixVersions.stable;
              nix.extraOptions = "experimental-features = nix-command flakes";
              system.stateVersion = "22.05";
            })

            home-manager.nixosModules.home-manager
            ({ pkgs, unstable, ... }: {
              home-manager.useGlobalPkgs = true;
              home-manager.users.rowan =
                { config, pkgs, ... }:
                import ./home.nix {
                  inherit config pkgs;
                  specialArgs = {
                    isGraphical = false;
                    unstable = unstable;
                    agenix = agenix;
                  };
                };
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
                  # Forward register db
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

              # Removed since connected to router via ethernet, register switch connected via wifi extender
              ## Set the eno1 interface to use the 192.168.0.* subnet so it can talk to the registers
              ## and add static routes to the registers
              #networking.interfaces.eno1.ipv4 = {
              #  addresses = [ {
              #    address = "192.168.0.60";
              #    prefixLength = 24;
              #  } ];
              #  routes = [
              #    { address = "192.168.0.121"; prefixLength = 32; }
              #    { address = "192.168.0.122"; prefixLength = 32; }
              #  ];
              #};
              ## But remove all other routes via ethernet so it doesn't mess up using the wifi for internet
              #networking.localCommands = ''
              #  ip route del 192.168.0.0/24 dev eno1 proto kernel scope link src 192.168.0.60
              #'';

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
                settings = {
                  X11Forwarding = true; # To use the graphical Tyro terminal adapter Configuration.exe
                  PasswordAuthentication = false;
                  PermitRootLogin = "no";
                };
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
              programs.fish.enable = true;

              nix.package = pkgs.nixVersions.stable;
              nix.extraOptions = "experimental-features = nix-command flakes";
              system.stateVersion = "20.03"; # Did you read the comment?
            })

            home-manager.nixosModules.home-manager
            ({ pkgs, unstable, ... }: {
              home-manager.useGlobalPkgs = true;
              home-manager.users.rowan =
                { config, pkgs, ... }:
                import ./home.nix {
                  inherit config pkgs;
                  specialArgs = {
                    isGraphical = false;
                    unstable = unstable;
                    agenix = agenix;
                  };
                };
            })
          ];
        };

      packages.x86_64-linux.shedPowerMonitor = shedPowerMonitor.package;
      devShells.x86_64-linux.shedPowerMonitor = pkgs.mkShell {
        buildInputs = [ pkgs.nodejs pkgs.nodePackages.node2nix ];
        NODE_PATH = shedPowerMonitor.NODE_PATH;
        shellHook = ''
          cd applications/shed-power-monitor;
          cat <<EOF
          Run:
              cat index.js | sed 's/DEVICE_PLACEHOLDER/\/dev\/vedirect-usb/' | node
          EOF
        '';
      };

      nixosConfigurations.farm-server =
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {inherit pkgs unstable;};
          modules = [

            #autofarm.nixosModule
            #({config, ...}: {
            #  services.autofarm = {
            #    deviceMonitorDeviceListenerPort = 9222;
            #    ecronServerEcrontab = "/home/rowan/.autofarm/ecrontab";
            #    frontendServerBasicAuthCredentialsFile = config.age.secrets."autofarm-frontend-server-basic-auth-credentials".path;
            #    deviceMonitorInfluxdbPort = 8086;
            #  };
            #  environment.systemPackages = [ pkgs.influxdb ];
            #})
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
              environment.systemPackages = [ pkgs.influxdb ];
              # On first start of influxdb:
              #   $ influx
              #   > CREATE USER <user> WITH PASSWORD '<password>' WITH ALL PRIVILEGES
              # Query users:
              #   > SHOW USERS
              # Database management:
              #   > CREATE DATABASE shed_power
              # Query data:
              #   > USE shed_power
              #   > SELECT * FROM battery_voltage
              services.influxdb.enable = true;
              # On first start of grafana:
              # - log in with admin/admin, set admin password, create other users
              # - create data-source pointing at influxdb http://localhost:8086
              # - create dashboard with shed-power signals
              services.grafana = {
                enable = true;
                settings = {};
              };
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
                  { localPort = 8123; remotePort = 8123; } # Home Assistant
                ];
              };
            })

            ({config, pkgs, ...}: {
              services.home-assistant = {
                enable = true;
                extraComponents = [
                  # Components required to complete the onboarding
                  "esphome"
                  "met"
                  "radio_browser"
                  "zha" # for zigbee
                  "http"
                ];
                config = {
                  # Includes dependencies for a basic setup
                  # https://www.home-assistant.io/integrations/default_config/
                  default_config = {};
                  automation = "!include automations.yaml";
                  http = {
                    use_x_forwarded_for = true;
                    trusted_proxies = [ "::1" ];
                  };
                  influxdb = {}; # The database "home_assistant" needs to be created manually
                };
              };
              networking.firewall.allowedTCPPorts = [ 8123 ];
            })

            ({config, pkgs, ...}: {
              imports =
                [./machines/farm-server-hardware-configuration.nix
                ];
              networking.hostName = "farm-server";
              networking.networkmanager.enable = true;
              networking.useDHCP = false;
              networking.interfaces.enp3s0.useDHCP = true;

              # Use the systemd-boot EFI boot loader.
              boot.loader.grub.enable = true;
              boot.loader.grub.device = "/dev/sda";

              # Default hardware-configuration has no swap device,
              # causing nixos-rebuilt to crash
              swapDevices = pkgs.lib.mkOverride 5 [
                {
                  device = "/swapfile";
                  size = 3000; # MB
                }
              ];

              # Select internationalisation properties.
              i18n.defaultLocale = "en_AU.UTF-8";
              # Set your time zone.
              time.timeZone = "Australia/Melbourne";

              services.openssh = {
                enable = true;
                settings = {
                  PasswordAuthentication = false;
                  PermitRootLogin = "no";
                  X11Forwarding = false;
                };
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
              programs.fish.enable = true;

              nix.package = pkgs.nixVersions.stable;
              nix.extraOptions = "experimental-features = nix-command flakes";
              system.stateVersion = "20.03"; # Did you read the comment?
            })

            home-manager.nixosModules.home-manager
            ({ pkgs, unstable, ... }: {
              home-manager.useGlobalPkgs = true;
              home-manager.users.rowan =
                { config, pkgs, ... }:
                import ./home.nix {
                  inherit config pkgs;
                  specialArgs = {
                    isGraphical = false;
                    unstable = unstable;
                    agenix = agenix;
                  };
                };
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
        let pkgs = unstable;
        in
        nixpkgs-unstable.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {inherit pkgs unstable;};
          modules = [

            ({...}: {
              networking.extraHosts = ''
                127.0.0.1 energy-queensland.localtest.me
              '';
            })

            agenix.nixosModules.age
            ({...}: {
              age.secrets."b2-credentials".file = ./secrets/b2-credentials.age;
              age.secrets."restic-password".file = ./secrets/restic-password.age;
              age.identityPaths = [ "/home/rowan/.ssh/id_rowan2" ];
            })

            home-manager.nixosModules.home-manager
            ({ pkgs, unstable, ... }: {
              home-manager.useGlobalPkgs = true;
              home-manager.users.rowan =
                { config, lib, pkgs, ... }:
                import ./home.nix {
                  inherit lib config pkgs;
                  specialArgs = {
                    isGraphical = true;
                    unstable = unstable;
                    agenix = agenix;
                  };
                };
            })

            kmonad.nixosModules.default
            ({lib, ...}: {
              services.kmonad = {
                enable = true;
                package = kmonad.packages.x86_64-linux.default;
                keyboards = {
                  texKeyboard = {
                    device = "/dev/tex-kbd";
                    config = builtins.readFile ./dotfiles/.config/kmonad/base.kbd;
                    defcfg = {
                      enable = true;
                      fallthrough = true;
                      allowCommands = false;
                    };
                  };
                  builtinKeyboard = {
                    device = "/dev/input/by-path/platform-i8042-serio-0-event-kbd";
                    config = builtins.readFile ./dotfiles/.config/kmonad/base.kbd;
                    defcfg = {
                      enable = true;
                      fallthrough = true;
                      allowCommands = false;
                    };
                  };
                  usbMacKeyboard = {
                    device = "/dev/mac-kbd";
                    config = builtins.readFile ./dotfiles/.config/kmonad/mac-kbd-base.kbd;
                    defcfg = {
                      enable = true;
                      fallthrough = true;
                      allowCommands = false;
                    };
                  };
                };
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

            # usb oscilloscope
            ({ pkgs, ...}: {
              services.udev.packages = [ pkgs.openhantek6022 ];
              environment.systemPackages = [ pkgs.openhantek6022 ];
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
                efiSupport = true;
                enableCryptodisk = true;
                device = "nodev";
              };

              networking.hostName = "rowan-p14";
              networking.networkmanager.enable = true;

              services.tailscale.enable = true;
              # SSH to machines on a second tailnet by ProxyJumping via a container
              networking.nat.enable = true;
              networking.nat.internalInterfaces = ["ve-+"];
              networking.nat.externalInterface = "wlp0s20f3";
              networking.networkmanager.unmanaged = [ "interface-name:ve-*" ];
              containers.tailscaled = {
                autoStart = true;
                enableTun = true;
                privateNetwork = true;
                hostAddress = "192.168.100.10";
                localAddress = "192.168.100.11";
                config = { ... }: {
                  services.tailscale.enable = true;
                  services.openssh.enable = true;
                  services.openssh.settings.PermitRootLogin = "yes";
                };
              };
              #networking.firewall.allowedTCPPorts = [ 8000 ];

              time.timeZone = "Australia/Melbourne";

              # The global useDHCP flag is deprecated, therefore explicitly set to false here.
              # Per-interface useDHCP will be mandatory in the future, so this generated config
              # replicates the default behaviour.
              networking.useDHCP = false;
              networking.interfaces.enp0s31f6.useDHCP = true;
              networking.interfaces.wlp0s20f3.useDHCP = true;

              # Select internationalisation properties.
              i18n.defaultLocale = "en_AU.UTF-8";
              #fonts.packages = with pkgs; [ nerdfonts source-code-pro ];

              programs.gnupg.agent = {
                enable = true;
                enableSSHSupport = true;
              };
              services.xserver.updateDbusEnvironment = true;

              services.printing.enable = true;
              services.printing.drivers = [ pkgs.hplip ];

              virtualisation.docker.enable = true;

              # Comment these lines to disable gpu
              services.xserver.videoDrivers = [ "nvidia" ];
              hardware.nvidia.prime.intelBusId = "PCI:0:2:0";
              hardware.nvidia.prime.nvidiaBusId = "PCI:1:0:0";
              hardware.nvidia.prime.offload.enable = true;
              hardware.nvidia.modesetting.enable = true;
              hardware.graphics = {
                enable = true;
                enable32Bit = true;
              };
              hardware.nvidia-container-toolkit.enable = true;

              services.logind.lidSwitchDocked = "suspend";

              services.xserver.enable = true;
              services.xserver.displayManager.gdm.enable = true;
              services.xserver.desktopManager.gnome.enable = true;

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

              nix.package = pkgs.nixVersions.stable;
              nix.extraOptions = "experimental-features = nix-command flakes";
              nix.settings.trusted-users = [ "root" "rowan" ];
              system.stateVersion = "21.11";

              nixpkgs.config.allowUnfree = true;
              nixpkgs.config.segger-jlink.acceptLicense = true;
            })
          ];
      };

      # Steps to reproduce machine state:
      # - make sure bios is set to uefi boot
      # - boot from nixos live usb
      # - nix --extra-experimental-features nix-command --extra-experimental-features flakes run github:kirillrdy/nixos-installer/e887b94a444c7590e3dfb151565a8f1c8b184482 -- -device /dev/nvme0n1 -encrypt
      # - reboot
      # - install machine config
      #   - copy /home/rowan/.ssh from backup
      #   - git clone git@github.com:rskew/machine-configuration /home/users/rowan/machine-configuration
      #   - nixos-rebuild --user-remote-sudo switch --flake /home/rowan/machine-configuration#peanut-butter-toast
      # - reboot
      #   - log in to root, set user password, log out, log in as user
      # - "ssh-add -c" priv keys
      # - enable command-not-found on terminal
      #   - sudo nix-channel --add https://nixos.org/channels/nixos-unstable nixos
      #   - sudo nix-channel --update
      # - setup firefox
      #   - log in to firefox to get passwords and extensions
      #   - in about:config set ui.key.menuAccessKeyFocuses to false to disable showing menu when pressing alt (xmonad mod key)
      # - to enable backups, add password files to /home/rowan/secrets/
      #   - restic-password for this machine's restic backup repository
      #   - restic-b2-appkey.env with B2_ACCOUNT_ID and B2_ACCOUNT_KEY
      nixosConfigurations.peanut-butter-toast =
        let pkgs = unstable;
        in
        nixpkgs-unstable.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {inherit pkgs unstable;};
          modules = [

            home-manager.nixosModules.home-manager
            ({ pkgs, unstable, ... }: {
              home-manager.useGlobalPkgs = true;
              home-manager.users.rowan =
                { config, pkgs, lib, ... }:
                import ./home.nix {
                  inherit config pkgs lib;
                  specialArgs = {
                    isGraphical = true;
                    unstable = unstable;
                    agenix = agenix;
                  };
                };
            })

            kmonad.nixosModule
            ({lib, ...}: {
              services.kmonad = {
                enable = true;
                configfiles = [
                  "/etc/kmonad/tex-usb-config.kbd"
                ];
                package = kmonad.packages.x86_64-linux.kmonad;
                make-group = false;
              };
              environment.etc."kmonad/tex-usb-config.kbd".source = pkgs.substitute {
                name = "config.kbd";
                src = ./dotfiles/.config/kmonad/base.kbd;
                substitutions = [ "--replace" "keyboard-device" "/dev/input/by-path/pci-0000:00:14.0-usbv2-0:6:1.0-event-kbd" ];
              };
            })

            # usb oscilloscope
            ({ pkgs, ...}: {
              services.udev.packages = [ pkgs.openhantek6022 ];
              environment.systemPackages = [ pkgs.openhantek6022 ];
            })

            ({config, pkgs, unstable, ...}: {
              imports = [ ./machines/peanut-butter-toast-hardware-configuration.nix ];
              security.tpm2.enable = false; # prevents "a start job is running for /dev/tpmrm0 ( _ / 1min 30s)"

              boot.loader.systemd-boot.enable = true;
              boot.loader.efi.canTouchEfiVariables = true;

              networking.hostId = "00000000";
              networking.hostName = "rowan-peanut-butter-toast";

              services.tailscale.enable = true;
              # SSH to machines on a second tailnet by ProxyJumping via a container
              networking.nat.enable = true;
              networking.nat.internalInterfaces = ["ve-+"];
              networking.nat.externalInterface = "wlp3s0";
              networking.networkmanager.unmanaged = [ "interface-name:ve-*" ];
              containers.tailscaled = {
                autoStart = true;
                enableTun = true;
                privateNetwork = true;
                hostAddress = "192.168.100.10";
                localAddress = "192.168.100.11";
                config = { ... }: {
                  services.tailscale.enable = true;
                  services.openssh.enable = true;
                  services.openssh.settings.PermitRootLogin = "yes";
                };
              };

              programs.gnupg.agent = {
                enable = true;
                enableSSHSupport = true;
              };

              time.timeZone = "Australia/Melbourne";

              virtualisation.docker.enable = true;

              users.users.rowan = {
                isNormalUser = true;
                extraGroups = [ "wheel" "docker" "dialout" ];
                shell = pkgs.fish;
              };
              programs.fish.enable = true;
              programs.fish.vendor.completions.enable = true;

              services.xserver.enable = true;
              services.xserver.displayManager.gdm.enable = true;
              services.xserver.desktopManager.gnome.enable = true;
              services.xserver.videoDrivers = [ "amdgpu" ];
              hardware.graphics = {
                enable = true;
                enable32Bit = true;
                extraPackages = [ pkgs.amdvlk ];
                extraPackages32 = [ pkgs.driversi686Linux.amdvlk ];
              };
              systemd.services.lactd.wantedBy = ["multi-user.target"];
              systemd.packages = [ pkgs.lact ];
              environment.systemPackages = [
                pkgs.lact
              ];

              nix.extraOptions = "experimental-features = nix-command flakes";
              nix.settings.trusted-users = [ "root" "rowan" ];
              system.stateVersion = "24.11";
            })
          ];
      };
    };
}

{ config, lib, ... }:
let
  cfg = config.services.wgToVps;
  net = cfg.network;
  exposeOf = c: c.expose or [ ];
  exposeRule = e:
    ''iifname "wg0" ip daddr ${e.host} tcp dport { ${lib.concatMapStringsSep ", " 
toString e.ports} } accept'';
in
{ 
  options.services.wgToVps = {
    enable = lib.mkEnableOption "WireGuard link to/from the multi-purpose VPS";
    role = lib.mkOption { type = lib.types.enum [ "vps" "client" ]; };
    privateKeyFile = lib.mkOption { type = lib.types.path; };
    network = lib.mkOption {
      type = lib.types.attrs;
      default = import ./wg-network.nix;
    };
    clientName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
    };
  };
  
  config = lib.mkIf cfg.enable (lib.mkMerge [
  
    { # a destination may map to only one wg peer: catch cross-site
      # address collisions at eval time instead of as silent misrouting
      assertions = [{
        assertion = 
          let addrs = lib.concatLists (lib.mapAttrsToList
                (_: c: [ c.wgIp ] ++ map (e: e.host) (exposeOf c)) net.clients);
          in lib.unique addrs == addrs;
        message = "wg-network.nix: wgIps and exposed hosts must be unique across all
clients";
      }];
    }

    (lib.mkIf (cfg.role == "vps") {
      networking.firewall.allowedUDPPorts = [ net.vps.listenPort ];
              networking.wireguard.interfaces.wg0 = {
        ips = [ "${net.vps.wgIp}/24" ];
        listenPort = net.vps.listenPort;
        privateKeyFile = cfg.privateKeyFile;
        peers = lib.mapAttrsToList (_: c: {
          publicKey = c.publicKey;
          allowedIPs = [ "${c.wgIp}/32" ]
            ++ lib.unique (map (e: "${e.host}/32") (exposeOf c));
        }) net.clients;
      };
    })
    
    (lib.mkIf (cfg.role == "client") (
      let 
        c = net.clients.${cfg.clientName};
        hasExpose = exposeOf c != [ ];
      in {
        networking.wireguard.interfaces.wg0 = {
          ips = [ "${c.wgIp}/24" ];
          privateKeyFile = cfg.privateKeyFile;
          peers = [{
            publicKey = net.vps.publicKey;
            endpoint = net.vps.endpoint;
            allowedIPs = [ "${net.vps.wgIp}/32" ];
            persistentKeepalive = 25;
          }];
        };
        networking.nat = lib.mkIf hasExpose {
          enable = true;
          internalInterfaces = [ "wg0" ];
          externalInterface = c.lanInterface or "eth0";
        };
        networking.nftables.enable = lib.mkIf hasExpose true;
        networking.firewall.extraForwardRules = lib.mkIf hasExpose ''
          ${lib.concatMapStringsSep "\n" exposeRule (exposeOf c)}
          iifname "wg0" drop
        '';
      }
    ))
  ]);
} 

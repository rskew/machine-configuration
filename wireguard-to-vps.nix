{ privateKeyFile, wgNetwork, hostName, lib }:
let
  exposeOf = c: c.expose or [ ];
  exposeRule = e:
    ''iifname "wg0" ip daddr ${e.host} tcp dport { ${lib.concatMapStringsSep ", " 
toString e.ports} } accept'';
in
lib.mkMerge [

  { # a destination may map to only one wg peer: catch cross-site
    # address collisions at eval time instead of as silent misrouting
    assertions = [{
      assertion =
        let addrs = lib.concatLists (lib.mapAttrsToList
              (_: c: [ c.wgIp ] ++ map (e: e.host) (exposeOf c)) wgNetwork.clients);
        in lib.unique addrs == addrs;
      message = "wgNetwork: wgIps and exposed hosts must be unique across all
ients";
    }];
  }

  (lib.mkIf (hostName == wgNetwork.vps.hostName) {
    networking.firewall.allowedUDPPorts = [ wgNetwork.vps.listenPort ];
            networking.wireguard.interfaces.wg0 = {
      ips = [ "${wgNetwork.vps.wgIp}/24" ];
      listenPort = wgNetwork.vps.listenPort;
      privateKeyFile = privateKeyFile;
      peers = lib.mapAttrsToList (_: c: {
        publicKey = c.publicKey;
        allowedIPs = [ "${c.wgIp}/32" ]
          ++ lib.unique (map (e: "${e.host}/32") (exposeOf c));
      }) wgNetwork.clients;
    };
  })
  
  (lib.mkIf (hostName != wgNetwork.vps.hostName) (
    let
      c = wgNetwork.clients.${hostName};
      hasExpose = exposeOf c != [ ];
    in {
      networking.wireguard.interfaces.wg0 = {
        ips = [ "${c.wgIp}/24" ];
        privateKeyFile = privateKeyFile;
        peers = [{
          publicKey = wgNetwork.vps.publicKey;
          endpoint = wgNetwork.vps.endpoint;
          allowedIPs = [ "${wgNetwork.vps.wgIp}/32" ];
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
]

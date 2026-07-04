# Single source of truth for the VPS <-> satellite WireGuard network.
# The VPS derives its peer list (routing + allowedIPs) from this; each
# client derives its tunnel, NAT, and forward-chain rules from its own
# entry. Exposed LAN hosts are routed as /32s because site subnets
# overlap (everything is 192.168.1.0/24), so every exposed host is
# listed explicitly.
{
  vps = let listenPort = 51820; in {
    hostName = "rowan-vps1";
    endpoint = "rowanskewes.com:${listenPort}";
    publicKey = "pW7Rd/G5f5CR40TR1KOgLh3M+nF2ZV7ZIXjCT/h2KEs=";
    wgIp = "10.100.0.1";
    inherit listenPort;
  };
  
  clients = {
    shop-server = {
      publicKey = "xJUD5yIJBVeF19kRc3AD2ohsg+yjtQli54ZfXHKzvnA=";
      wgIp = "10.100.0.2";
      lanInterface = "eth0";
      expose = [
        { host = "192.168.1.121"; ports = [ 6677 5432 ]; }  # register master: fb-reader + register DB
        { host = "192.168.1.122"; ports = [ 6677 ]; }       # register 2: fb-reader
      ];
    };
    farm-server-wyse = {
      publicKey = "1TKilt4Xjr7brRhrfC70HaXzbAoN9t2jLCkZFZ4GxRo=";
      wgIp = "10.100.0.3";
    };
  };
}

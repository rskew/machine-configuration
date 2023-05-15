{ lib, ... }: {
  # This file was populated at runtime with the networking
  # details gathered from the active system.
  networking = {
    nameservers = [ "8.8.8.8"
 ];
    defaultGateway = "45.124.54.1";
    dhcpcd.enable = false;
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces = {
      eth0 = {
        ipv4.addresses = [
          { address="45.124.54.206"; prefixLength=24; }
        ];
        ipv6.addresses = [
          { address="fe80::216:3eff:fee3:beb4"; prefixLength=64; }
        ];
        ipv4.routes = [ { address = "45.124.54.1"; prefixLength = 32; } ];
      };
      
    };
  };
  services.udev.extraRules = ''
    ATTR{address}=="00:16:3e:e3:be:b4", NAME="eth0"
    
  '';
}

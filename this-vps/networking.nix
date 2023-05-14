{ lib, ... }: {
  # This file was populated at runtime with the networking
  # details gathered from the active system.
  networking = {
    nameservers = [ "8.8.8.8"
 ];
    defaultGateway = "119.42.53.1";
    defaultGateway6 = {
      address = "";
      interface = "eth0";
    };
    dhcpcd.enable = false;
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces = {
      eth0 = {
        ipv4.addresses = [
          { address="119.42.53.134"; prefixLength=24; }
        ];
        ipv6.addresses = [
          { address="fe80::216:3eff:fee3:bde9"; prefixLength=64; }
        ];
        ipv4.routes = [ { address = "119.42.53.1"; prefixLength = 32; } ];
      };
      
    };
  };
  services.udev.extraRules = ''
    ATTR{address}=="00:16:3e:e3:bd:e9", NAME="eth0"
    
  '';
}

{ config, lib, pkgs, ... }:

{
  imports =
    [
      ../hardware-configuration.nix
      ../terminal-environment.nix
    ]; 

  networking.hostName = "shop-server";

  networking.networkmanager.enable = true;

  environment.systemPackages = with pkgs; [
    pgcli
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
  console = {
    font = "source-code-pro";
    keyMap = "us";
  };

  # Set your time zone.
  time.timeZone = "Australia/Melbourne";

  services.openssh = {
    enable = true;
    passwordAuthentication = false;
    permitRootLogin = "no";
    forwardX11 = false;
  };
  systemd.services.ssh-tunnel = import ../persistent-ssh-tunnel.nix {
    inherit pkgs;
    local-port = "22";
    remote-ip = "103.236.163.87";
    remote-port = "9922";
    remote-user = "rowan";
    id-file = "/home/rowan/.ssh/id_ed25519_mammoth";
    known-hosts-line = "103.236.163.87 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIk/U6LB/hjlBCWtJqHZgKnzOQmmOw4GKntvvdrYYYGLdDoFZomYXwbEWexU/IHR5PiNIU4RuVSXdoPxGVU9YPg=";
  };

  users.users.rowan = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC3oUx8oe0xQDKP9sw602ku4wOhP9AKLXNsGDARyLdw+MbBzGJTNFUvh6fj77fWYTqHlDnrfgoBlc5mS0uY9KUP/28PjfyqdIkGdhbfE403+vp4a1JMAnVv7xV6n3PYtiUYIF5hwCSzeiibIhQsCTsJGtMoiECdRpOvqCD11m6kTA1j5xlajEnvnNg7k7W+MaZWaqeuvEn0Vi7tu+Ia6xvnfkKwph9VpVuMsTrAy0y36pSpglax2yKEV53lt8ZGnasJiOu2fv2yT6np9qGizU2I8ccC5G9nNCkYHJsE2q1ogjdltva6oexCOJzLwMVZCC6UVTHej0494ipY35JSJmh3TW6oG8ddhdUdurPQNaw/w5tiUZwEG3640Ts3TbIJ0sagi1+l5TBRpW7wsgU8VbTyBvsMszXj46xri4jleESPVjr820CRnt27l2Dt/DGpdZHvhbB3endb0NkEqfMb/44SP6mXceT10GIBiCl110/7n7qehXyr1qt88VZ6QVbige9ts9NVkoNYkBrxaHq4ooa8IV9leO52m0X7BLDYSEUYBMFWx3lc7vbyvCV382gsfTQA/CtBHmEUTlljSQS7ZDOXwiSZYXeDKtafDTRNBrWr3HikgjnqMK2OjLU/y3nyoVtE9FzLANWuxwhJIld9S44QWZA82LsnrW/hQfXp7Y4VyQ== rowan@rowanX220"
    ];
    shell = "/run/current-system/sw/bin/fish";
  };

  nix.trustedUsers = [ "root" "rowan" ];

  system.stateVersion = "20.03"; # Did you read the comment?
}

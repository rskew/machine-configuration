{ config, pkgs, ... }:

{
  imports =
    [
      ../hardware-configuration.nix
      ../terminal-environment.nix
    ];

  networking.hostName = "farm-server-digital";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.useDHCP = false;
  networking.interfaces.enp3s0.useDHCP = true;

  time.timeZone = "Australia/Melbourne";

  environment.systemPackages = with pkgs; [
  ];

  services.openssh = {
    enable = true;
    passwordAuthentication = false;
    permitRootLogin = "no";
    forwardX11 = false;
  };
  # Persistent SSH tunnel with mammoth vps jump box for remote access
  systemd.services.ssh-tunnel = import ../persistent-ssh-tunnel.nix {
    inherit pkgs;
    local-port = "22";
    remote-port = "7722";
    remote-ip = "103.236.163.87";
    remote-user = "rowan";
    id-file = "/home/rowan/.ssh/id_ed25519_mammoth";
    known-hosts-line = "103.236.163.87 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIk/U6LB/hjlBCWtJqHZgKnzOQmmOw4GKntvvdrYYYGLdDoFZomYXwbEWexU/IHR5PiNIU4RuVSXdoPxGVU9YPg=";
  };

  users.users.rowan = {
    isNormalUser = true;
    home = "/home/rowan";
    uid = 1000;
    extraGroups = [ "wheel" "usb" "dialout" "uucp" "docker" ];
    shell = "/run/current-system/sw/bin/fish";
    openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC3oUx8oe0xQDKP9sw602ku4wOhP9AKLXNsGDARyLdw+MbBzGJTNFUvh6fj77fWYTqHlDnrfgoBlc5mS0uY9KUP/28PjfyqdIkGdhbfE403+vp4a1JMAnVv7xV6n3PYtiUYIF5hwCSzeiibIhQsCTsJGtMoiECdRpOvqCD11m6kTA1j5xlajEnvnNg7k7W+MaZWaqeuvEn0Vi7tu+Ia6xvnfkKwph9VpVuMsTrAy0y36pSpglax2yKEV53lt8ZGnasJiOu2fv2yT6np9qGizU2I8ccC5G9nNCkYHJsE2q1ogjdltva6oexCOJzLwMVZCC6UVTHej0494ipY35JSJmh3TW6oG8ddhdUdurPQNaw/w5tiUZwEG3640Ts3TbIJ0sagi1+l5TBRpW7wsgU8VbTyBvsMszXj46xri4jleESPVjr820CRnt27l2Dt/DGpdZHvhbB3endb0NkEqfMb/44SP6mXceT10GIBiCl110/7n7qehXyr1qt88VZ6QVbige9ts9NVkoNYkBrxaHq4ooa8IV9leO52m0X7BLDYSEUYBMFWx3lc7vbyvCV382gsfTQA/CtBHmEUTlljSQS7ZDOXwiSZYXeDKtafDTRNBrWr3HikgjnqMK2OjLU/y3nyoVtE9FzLANWuxwhJIld9S44QWZA82LsnrW/hQfXp7Y4VyQ== rowan@rowanX220"
    ];
  };

  system.stateVersion = "20.03"; # Did you read the comment?
}


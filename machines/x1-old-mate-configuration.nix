{ config, pkgs, ... }:

let
  machine-url = "farm.rowanskewes.com";
  dynamic-dns-update-url = "${pkgs.lib.fileContents ../secrets/dynamic-dns-url.txt}?hostname=${machine-url}";
in
{
  imports =
    [ # Include the results of the hardware scan.
      ../hardware-configuration.nix
      ../terminal-environment.nix
      # This machine is now the farm server
      /home/rowan/projects/autofarm/cns/irrigation-control-configuration.nix
    ];

  # Use the GRUB 2 boot loader
  boot.loader.grub = {
    enable = true;
    version = 2;
    efiSupport = true;
    device = "/dev/sda"; # or "nodev" for efi only
  };

  networking.hostName = "ro-X1";
  networking.wireless.enable = true;

  # Set your time zone.
  time.timeZone = "Australia/Melbourne";

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
    vim
    git
    tree
    fish
    rxvt_unicode
    zip
    unzip
    fzf
    ripgrep
    bashmount
    filelight
    iotop
    docker
    docker_compose
    jq
    pulsemixer
    brightnessctl
  ];

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    passwordAuthentication = false;
    permitRootLogin = "no";
    forwardX11 = false;
  };

  security.sudo.wheelNeedsPassword = false;

  users.users.rowan = {
    isNormalUser = true;
    home = "/home/rowan";
    uid = 1000;
    extraGroups = [ "wheel" "audio" "usb" "fuse" "video" "dialout" "uucp" "sound" "pulse" "libvirtd" "docker" ];
    shell = "/run/current-system/sw/bin/fish";
    openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC3oUx8oe0xQDKP9sw602ku4wOhP9AKLXNsGDARyLdw+MbBzGJTNFUvh6fj77fWYTqHlDnrfgoBlc5mS0uY9KUP/28PjfyqdIkGdhbfE403+vp4a1JMAnVv7xV6n3PYtiUYIF5hwCSzeiibIhQsCTsJGtMoiECdRpOvqCD11m6kTA1j5xlajEnvnNg7k7W+MaZWaqeuvEn0Vi7tu+Ia6xvnfkKwph9VpVuMsTrAy0y36pSpglax2yKEV53lt8ZGnasJiOu2fv2yT6np9qGizU2I8ccC5G9nNCkYHJsE2q1ogjdltva6oexCOJzLwMVZCC6UVTHej0494ipY35JSJmh3TW6oG8ddhdUdurPQNaw/w5tiUZwEG3640Ts3TbIJ0sagi1+l5TBRpW7wsgU8VbTyBvsMszXj46xri4jleESPVjr820CRnt27l2Dt/DGpdZHvhbB3endb0NkEqfMb/44SP6mXceT10GIBiCl110/7n7qehXyr1qt88VZ6QVbige9ts9NVkoNYkBrxaHq4ooa8IV9leO52m0X7BLDYSEUYBMFWx3lc7vbyvCV382gsfTQA/CtBHmEUTlljSQS7ZDOXwiSZYXeDKtafDTRNBrWr3HikgjnqMK2OjLU/y3nyoVtE9FzLANWuxwhJIld9S44QWZA82LsnrW/hQfXp7Y4VyQ== rowan@rowanX220"
    ];
  };

  nix.trustedUsers = [ "root" "rowan" ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "20.03"; # Did you read the comment?

  # Dynamic DNS
  systemd.services.dynamic-dns = {
    serviceConfig.Type = "oneshot";
    script = ''
        RESPONSE="$(${pkgs.curl}/bin/curl --silent ${dynamic-dns-update-url})"
        echo "$(date -Iseconds) ''${RESPONSE}" >> /var/log/dynamic-dns.log
    '';
  };
  systemd.timers.dynamic-dns = {
    wantedBy = [ "timers.target" ];
    partOf = [ "dynamic-dns.service" ];
    timerConfig.OnCalendar = "*-*-* *:*:00";
  };
}

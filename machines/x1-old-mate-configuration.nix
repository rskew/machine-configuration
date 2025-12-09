{ config, pkgs, ... }:

{
  imports =
    [ ../hardware-configuration.nix
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
    emacs
    sl

    #utilities
    htop
    git
    wget
    sl

    # For nicer terminal experience over ssh
    rxvt_unicode
    vim
    byobu # use the byobu-tmux command
    tmux

    # For querying BIOS settings from inside linux
    dmidecode
  ];

  # Use fish shell
  programs.fish.enable = true;

  # vi mode in terminal
  programs.bash.interactiveShellInit = ''
    set -o vi
    alias byobu=byobu-screen
  '';

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    passwordAuthentication = false;
    permitRootLogin = "no";
    forwardX11 = false;
  };
  systemd.services.ssh-tunnel = import ../persistent-ssh-tunnel.nix {
    inherit pkgs;
    local-port = "22";
    remote-ip = "45.124.52.135";
    remote-port = "6622";
    remote-user = "rowan";
    id-file = "/home/rowan/.ssh/id_ed25519_mammoth";
    known-hosts-line = "103.236.163.87 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIk/U6LB/hjlBCWtJqHZgKnzOQmmOw4GKntvvdrYYYGLdDoFZomYXwbEWexU/IHR5PiNIU4RuVSXdoPxGVU9YPg=";
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

  system.stateVersion = "20.03"; # Did you read the comment?

  hardware.bluetooth.enable = false;
  services.logind.lidSwitch = "ignore";
}

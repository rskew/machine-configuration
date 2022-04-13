# Machines

To run one of these machine configs:
```sh
sudo nixos-rebuild switch --flake .#some-machine-name
```

Tweaks required when copying one of these machine configurations:

- update the boot config (e.g. `boot.initrd.luks.devices.root.device`)
- change `networking.hostName`
Backups are configured to use a key in `/home/rowan/secrets`

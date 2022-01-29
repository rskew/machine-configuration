# Machines

To run one of these machine configs:

- `ln -s machines/<the-machine-you-want-to-run>.nix configuration.nix`
- add the unstable channel (if you haven't already) with `nix-channel --add https://nixos.org/channels/nixos-unstable`
- `nixos-rebuild switch`

Each `*-configuration.nix` will require tweaking. At the very least:

- update the boot config (e.g. `boot.initrd.luks.devices.root.device`)
- change `networking.hostName`

There are also things like backups configured to use a key in `/etc/nixos/secrets/` you'll need to edit or remove.

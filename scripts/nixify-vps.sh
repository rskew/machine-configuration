#!/usr/bin/env bash
# binarylane:
# - create instance
# - switch off port blocking via web control panel
# - add entry to ssh config
# - scp ~/.ssh/id_to_deploy_to_servers1* newhost:/home/rowan/.ssh/

set -euxo pipefail

function usage {
    echo "Usage: nixify-vps.sh name-of-host-in-ssh-config name-of-nixos-configuration-in-flake"
}


SSH_HOST=${1-}
if [ -z "$SSH_HOST" ]; then
    usage
    exit 1
fi

ssh root@"$SSH_HOST" git clone https://github.com/elitak/nixos-infect.git

# Using PROVIDER=digitalocean causes nixos-infect to create a detailed
# networking config, also required by mammoth/binarylane.
# This command sometimes exits with failure status because the remote closes
# the ssh connection upon completion of installation, so silence errors.
ssh root@"$SSH_HOST" "cd nixos-infect; chmod +x nixos-infect; PROVIDER=digitalocean ./nixos-infect"

################# The Rest Needs Testing #####################
####### For now just run the following stuff manually ########

# wait for network services to restart on the remote server after nixos installation
for i in 1 2 3 4 5; do ssh root@"$SSH_HOST" echo hi && break || sleep 2; done

NIXOS_CONFIGURATION=${2-}
if [ -z "$NIXOS_CONFIGURATION" ]; then
    usage
    exit 1
fi

ssh root@"$SSH_HOST" nix-shell -p git --command '"git clone https://github.com/rskew/machine-configuration.git"'
ssh root@"$SSH_HOST" mkdir -p /root/machine-configuration/machines/"$NIXOS_CONFIGURATION"
ssh root@"$SSH_HOST" cp /etc/nixos/hardware-configuration.nix /etc/nixos/networking.nix /root/machine-configuration/machines/"$NIXOS_CONFIGURATION"
ssh root@"$SSH_HOST" nix-shell -p git --command '"cd machine-configuration/machines/'$NIXOS_CONFIGURATION'; git add hardware-configuration.nix networking.nix -f"'

ssh root@"$SSH_HOST" mkdir /root/.ssh
ssh root@"$SSH_HOST" "cat - > /root/.ssh/known_hosts" << EOF
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
EOF

ssh -A root@"$SSH_HOST" nix-shell -p git --command "'nixos-rebuild switch --flake /root/machine-configuration#${NIXOS_CONFIGURATION}'"

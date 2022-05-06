#!/usr/bin/env bash

set -euxo pipefail

function usage {
    echo "Usage: nixify-mammoth-vps.sh name-of-host-in-ssh-config name-of-nixos-configuration-in-flake"
}

SSH_HOST=${1-}
if [ -z "$SSH_HOST" ]; then
    usage
    exit 1
fi

NIXOS_CONFIGURATION=${2-}
if [ -z "$NIXOS_CONFIGURATION" ]; then
    usage
    exit 1
fi

ssh $SSH_HOST git clone https://github.com/elitak/nixos-infect.git

# Using PROVIDER=digitalocean causes nixos-infect to create a detailed
# networking config, also required by mammoth
ssh $SSH_HOST "cd nixos-infect; PROVIDER=digitalocean ./nixos-infect"

#### To be tested
#ssh $SSH_HOST git clone https://github.com/rskew/machine-configuration.git
#
#ssh $SSH_HOST nix-shell --cmd "'nixos-rebuild switch --flake /root/machine-configuration#${NIXOS_CONFIGURATION}'"

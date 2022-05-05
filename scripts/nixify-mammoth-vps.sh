#!/usr/bin/env bash

set -euxo pipefail

SSH_HOST=${1-}
if [ -z "$SSH_HOST" ]; then
    echo "Usage: nixify-mammoth-vps.sh name-of-host-to-nixify-in-ssh-config"
    exit 1
fi

ssh $SSH_HOST git clone https://github.com/elitak/nixos-infect.git
# Using PROVIDER=digitalocean causes nixos-infect to create a detailed
# networking config, also required by mammoth
ssh $SSH_HOST "cd nixos-infect; PROVIDER=digitalocean ./nixos-infect"

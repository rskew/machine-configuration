#!/usr/bin/env bash

set -eux
nix build nixpkgs#lunarvim -o ~/gc-roots/result-lunarvim
cd ~/projects/notify_send_server && nix build .#server -o ~/gc-roots/result-notify-send-server
cd ~/harvest/admin-app \
    && nix build .#devShells.x86_64-linux.db -o ~/gc-roots/result-shop-app-db \
    && nix build .#devShells.x86_64-linux.erlang-backend -o ~/gc-roots/result-shop-app-erlang-backend \
    && nix build .#devShells.x86_64-linux.tabular-frontend -o ~/gc-roots/result-shop-app-tabular-frontend
cd ~/harvest/munge \
   && nix build .#devShells.x86_64-linux.munge -o ~/gc-roots/result-shop-app-munge
cd ~/farm/autofarm \
    && nix build .#devShells.x86_64-linux.autofarm -o ~/gc-roots/result-autofarm-shell \
    && nix build .#autofarm -o ~/gc-roots/result-autofarm-package
bash ~/silverpond/build-gc-roots.sh
nix build ~/scratch-projects/zigbee-farmnode#devShells.x86_64-linux.default -o ~/gc-roots/result-zigbee-farmnode

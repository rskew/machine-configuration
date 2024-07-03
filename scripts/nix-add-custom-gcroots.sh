#!/usr/bin/env bash

set -eux
cd ~/projects/notify_send_server && nix build .#server
cd ~/harvest/admin-app \
    && nix build .#devShells.x86_64-linux.db -o result-db \
    && nix build .#devShells.x86_64-linux.erlang-backend -o result-erlang-backend \
    && nix build .#devShells.x86_64-linux.tabular-frontend -o result-tabular-frontend
cd ~/harvest/munge \
   && nix build .#devShells.x86_64-linux.munge
cd ~/farm/autofarm \
    && nix build .#devShells.x86_64-linux.autofarm -o result-autofarm-shell \
    && nix build .#autofarm -o result-autofarm-package
bash ~/silverpond/build-gc-roots.sh

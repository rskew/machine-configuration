#!/usr/bin/env bash
# Launch devlog-player via the project's flake devShell.
#   --rebuild   force a fresh `cargo build` even if the binary looks current
# Other args are forwarded to the player.
set -euo pipefail

cd "$(dirname "$0")"

force=0
args=()
for arg in "$@"; do
    case "$arg" in
        --rebuild) force=1 ;;
        *) args+=("$arg") ;;
    esac
done

bin=target/release/devlog-player
need=0
if [ "$force" = "1" ] || [ ! -x "$bin" ]; then
    need=1
elif [ -n "$(find src Cargo.toml Cargo.lock -newer "$bin" -print 2>/dev/null | head -n1)" ]; then
    need=1
fi

if [ "$need" = "1" ]; then
    nix develop . --command cargo build --release --features gui --bin devlog-player
fi

exec nix develop . --command "$bin" "${args[@]}"

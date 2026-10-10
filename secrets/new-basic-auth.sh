#!/usr/bin/env bash
# Usage: ./new-basic-auth.sh <secret-name> <username> [password]
# Creates <secret-name>.age holding an nginx htpasswd line (bcrypt) and adds it
# to secrets.nix. If no password is given, one is generated and printed once.
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <secret-name> <username> [password]" >&2
  exit 1
fi

cd "$(dirname "$0")"

name="${1%.age}"
user="$2"
password="${3:-$(head -c 24 /dev/urandom | base64 | tr -d '/+=')}"
file="$name.age"

if [ -e "$file" ] || grep -qF "\"$file\"" secrets.nix; then
  echo "$file already exists or is already in secrets.nix" >&2
  exit 1
fi

# agenix reads recipients from secrets.nix, so the entry must exist before encrypting.
sed -i "s|^}$|  \"$file\".publicKeys = [ rowan vpsManagement idToDeployToServers ];\n}|" secrets.nix

# Password goes via stdin (-i) so it doesn't show up in the process list.
printf '%s' "$password" \
  | nix shell nixpkgs#apacheHttpd --command htpasswd -niB "$user" \
  | agenix -e "$file"

echo "Created $file for user '$user'"
if [ $# -lt 3 ]; then
  echo "Generated password: $password"
fi
echo "Add to flake.nix: age.secrets.$name.file = ./secrets/$file;"

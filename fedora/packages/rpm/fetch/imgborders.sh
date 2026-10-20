#!/usr/bin/env bash
set -euo pipefail

: "${RYOKU_FETCH_TREE:?}"
package=imgborders
dest="$RYOKU_FETCH_TREE/.rpm-$package/$package"
bundle="$RYOKU_FETCH_TREE/release/packages/$package/$package.bundle"
rm -rf "$dest"
mkdir -p "${dest%/*}"
git clone -q "$bundle" "$dest"

hyprland_version=$(pkg-config --modversion hyprland)
commit=$(grep -F "$hyprland_version" "$dest/hyprpm.toml" | grep -oE '[0-9a-f]{40}' | sed -n '2p' || true)
if [[ -z $commit ]]; then
  commit=$(git -C "$dest" rev-parse HEAD)
fi
[[ $commit =~ ^[0-9a-f]{40}$ ]]
git -C "$dest" checkout -q --detach "$commit"
[[ $(git -C "$dest" rev-parse HEAD) == "$commit" ]]
printf '%s\n' "$commit" > "$dest/.ryoku-source-commit"
rm -rf "$dest/.git"

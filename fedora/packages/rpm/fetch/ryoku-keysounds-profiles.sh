#!/usr/bin/env bash
set -euo pipefail

: "${RYOKU_FETCH_TREE:?}"
commit=326252a13e7bef4f1c35d08ef0189b5af6f8ba02
dest="$RYOKU_FETCH_TREE/.rpm-ryoku-keysounds-profiles/mechvibes"
rm -rf "$dest"
mkdir -p "${dest%/*}"
git clone -q https://github.com/hainguyents13/mechvibes.git "$dest"
git -C "$dest" checkout -q --detach "$commit"
[[ $(git -C "$dest" rev-parse HEAD) == "$commit" ]]
printf '%s\n' "$commit" > "$dest/.ryoku-source-commit"
rm -rf "$dest/.git"

#!/usr/bin/env bash
set -euo pipefail

commit=4b657407c98bbc8830ae66c2ac7ff3d737c55a83
destination=$RYOKU_FETCH_TREE/.rpm-ryoku-oh-my-zsh/oh-my-zsh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git -C "$work" init -q
git -C "$work" remote add origin https://github.com/ohmyzsh/ohmyzsh.git
git -C "$work" fetch -q --depth 1 origin "$commit"
resolved=$(git -C "$work" rev-parse FETCH_HEAD)
[[ $resolved == "$commit" ]] || {
  printf 'ryoku-oh-my-zsh: expected %s, fetched %s\n' "$commit" "$resolved" >&2
  exit 1
}
git -C "$work" -c advice.detachedHead=false checkout -q --detach "$commit"
rm -rf "$work/.git"
rm -rf "${destination%/*}"
mkdir -p "${destination%/*}"
mv "$work" "$destination"
trap - EXIT

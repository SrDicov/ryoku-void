#!/usr/bin/env bash
set -euo pipefail

commit=459c6714e31276f73025369e722cf4ab48eccbc3
version=0.1.0.r27.g459c671
expected=60b83e0663166035a5f81fa456d543ceb324d6286b9699f37d8a47fa460c39f7
sources=${RYOKU_FETCH_SOURCES:?RYOKU_FETCH_SOURCES is required}
tree=${RYOKU_FETCH_TREE:?RYOKU_FETCH_TREE is required}
archive="ryomanager-$commit.tar.gz"
url="https://github.com/Ryoku-dev/ryomanager/archive/$commit.tar.gz"

for tool in curl gzip npm sha256sum tar; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'fetch/ryomanager.sh: %s is required\n' "$tool" >&2
    exit 1
  }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$sources"
curl --fail --location --retry 3 --proto '=https' \
  "$url" -o "$work/$archive"
actual=$(sha256sum "$work/$archive")
actual=${actual%% *}
[[ $actual == "$expected" ]] || {
  printf 'fetch/ryomanager.sh: checksum mismatch (expected %s, got %s)\n' \
    "$expected" "$actual" >&2
  exit 1
}

tar -xzf "$work/$archive" -C "$work"
source_dir="$work/ryomanager-$commit"
[[ -f $source_dir/frontend/package-lock.json ]] || {
  printf 'fetch/ryomanager.sh: source archive has no frontend lockfile\n' >&2
  exit 1
}
(
  cd "$source_dir/frontend"
  npm ci
  rm -rf dist
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    --format=pax \
    --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
    -cf - node_modules \
    | gzip -n > "$sources/ryomanager-$version-node_modules.tar.gz"
)
install -m0644 "$tree/release/packages/ryomanager/ryomanager.desktop" \
  "$sources/ryomanager.desktop"

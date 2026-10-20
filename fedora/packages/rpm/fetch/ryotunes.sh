#!/usr/bin/env bash
set -euo pipefail

repo=Ryoku-dev/ryotunes
api=${RYOKU_GITHUB_API:-https://api.github.com}
download=${RYOKU_GITHUB_DL:-https://github.com}
sources=${RYOKU_FETCH_SOURCES:?RYOKU_FETCH_SOURCES is required}

die() {
  printf 'fetch/ryotunes.sh: %s\n' "$*" >&2
  exit 1
}

for tool in curl jq sha256sum tar gzip pnpm; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required"
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$sources"

auth=()
token=${GH_TOKEN:-${GITHUB_TOKEN:-}}
[[ -z $token ]] || auth=(-H "Authorization: Bearer $token")
release=$(curl -fsSL --retry 3 \
  -H 'Accept: application/vnd.github+json' \
  -H 'User-Agent: ryoku-fedora-source-fetch' \
  "${auth[@]}" "$api/repos/$repo/releases/latest") \
  || die "could not resolve the latest $repo release"

[[ $(jq -r '.draft' <<<"$release") == false ]] \
  || die 'latest release is a draft'
[[ $(jq -r '.prerelease' <<<"$release") == false ]] \
  || die 'latest release is a prerelease'
tag=$(jq -r '.tag_name // empty' <<<"$release")
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "latest release tag '$tag' is not vX.Y.Z"
version=${tag#v}
archive="ryotunes-$version.tar.gz"
sidecar="$archive.sha256"

for asset in "$archive" "$sidecar"; do
  count=$(jq --arg name "$asset" '[.assets[] | select(.name == $name)] | length' <<<"$release")
  [[ $count == 1 ]] || die "release $tag must contain exactly one $asset asset"
done

base="$download/$repo/releases/download/$tag"
curl -fsSL --retry 3 -o "$work/$archive" "$base/$archive" \
  || die "could not download $archive"
curl -fsSL --retry 3 -o "$work/$sidecar" "$base/$sidecar" \
  || die "could not download $sidecar"

mapfile -t lines < <(grep -vE '^[[:space:]]*$' "$work/$sidecar" || true)
(( ${#lines[@]} == 1 )) || die 'source checksum sidecar must contain one entry'
read -r expected filename extra <<<"${lines[0]}"
filename=${filename#\*}
[[ $expected =~ ^[0-9a-fA-F]{64}$ ]] || die 'source checksum is malformed'
[[ $filename == "$archive" && -z ${extra:-} ]] \
  || die "source checksum sidecar must name exactly $archive"
actual=$(sha256sum "$work/$archive")
actual=${actual%% *}
[[ ${actual,,} == "${expected,,}" ]] || die "sha256 mismatch for $archive"

tar -xzf "$work/$archive" -C "$work"
source_dir="$work/ryotunes-$version"
[[ -f $source_dir/Cargo.lock && -f $source_dir/ui/pnpm-lock.yaml ]] \
  || die "$archive does not contain the expected source tree"
grep -Eq "^version = \"$version\"$" "$source_dir/Cargo.toml" \
  || die "$archive Cargo workspace version does not match $version"

(
  cd "$source_dir/ui"
  pnpm install --frozen-lockfile \
    --virtual-store-dir=node_modules/.pnpm \
    --config.prefer-symlinked-executables=true
  rm -f node_modules/.modules.yaml node_modules/.pnpm-workspace-state-v1.json
  rm -rf .svelte-kit build
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    --format=pax \
    --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
    -cf - node_modules |
    gzip -n > "$sources/ryotunes-$version-node_modules.tar.gz"
)
install -m0644 "$work/$archive" "$sources/$archive"
printf '%s\n' "$version" > "$sources/.version"

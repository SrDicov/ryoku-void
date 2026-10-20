#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
out=$(realpath -m "${RYOKU_RPM_OUT:-$root/fedora/packages/rpm/out}")
srpm_input=${RYOKU_SRPM_IN:-}
mirror_input=${RYOKU_RPM_MIRROR:-}
local_build=${RYOKU_RPM_LOCAL:-0}
signing_key=${RYOKU_RPM_SIGNING_KEY:-}
die() { printf 'build-rpm-repo: %s\n' "$*" >&2; exit 1; }
for tool in rpmbuild createrepo_c cp find rpm go python3; do
  command -v "$tool" >/dev/null || die "missing $tool"
done
[[ $local_build == 0 || $local_build == 1 ]] || die 'RYOKU_RPM_LOCAL must be 0 or 1'
if [[ $local_build == 0 ]]; then
  [[ -n $signing_key ]] || die 'set RYOKU_RPM_SIGNING_KEY'
fi
if [[ -n $signing_key ]]; then
  for tool in gpg rpmkeys rpmsign; do
    command -v "$tool" >/dev/null || die "missing $tool"
  done
fi
if [[ -n $mirror_input ]]; then
  command -v dnf5 >/dev/null || die 'missing dnf5 for published RPM compatibility checks'
  [[ -n $signing_key ]] || die 'RYOKU_RPM_MIRROR requires RYOKU_RPM_SIGNING_KEY'
  mirror=$(realpath -m "$mirror_input")
  [[ -d $mirror ]] || die "RPM mirror is not a directory: $mirror_input"
fi

[[ ! -e $out ]] || die "output already exists: $out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out" "$work/RPMS"

if [[ -n $srpm_input ]]; then
  srpms=$(realpath -m "$srpm_input")
  [[ -d $srpms ]] || die "SRPM input is not a directory: $srpm_input"
else
  srpms="$work/SRPMS"
  RYOKU_SRPM_OUT="$srpms" "$root/fedora/packages/rpm/prepare-srpms.sh"
fi
[[ -f $srpms/release.json ]] || die "missing release metadata: $srpms/release.json"
upstream_manifest="$srpms/upstream-rpms.tsv"
[[ -f $upstream_manifest ]] \
  || die "missing upstream RPM identity manifest: $upstream_manifest"

# Before the builds, so a package without a translation row fails fast.
mapfile -t meta < <(python3 - "$srpms/release.json" <<'PYMETA'
import json
import sys

data = json.load(open(sys.argv[1]))
for key in ("release", "version", "commit", "channel"):
    print(data[key])
PYMETA
)
((${#meta[@]} == 4)) || die "could not read $srpms/release.json"
manifest_bin="$work/ryoku-manifest"
(cd "$root/ryoku/cli" && go build -mod=vendor -o "$manifest_bin" ./cmd/ryoku-manifest) \
  || die 'could not build cmd/ryoku-manifest'
"$manifest_bin" -repo "$root" -edition fedora -release "${meta[0]}" \
  -version "${meta[1]}" -commit "${meta[2]}" -channel "${meta[3]}" \
  -out "$out/manifest.json" \
  || die 'could not generate manifest.json'

keydb=
if [[ -n $signing_key ]]; then
  gpg --armor --export "$signing_key" > "$work/key.asc"
  keydb="$work/keydb"
  mkdir -p "$keydb"
  rpm --dbpath "$keydb" --initdb
  rpm --dbpath "$keydb" --import "$work/key.asc"
fi

is_debug_package() {
  [[ $1 == *-debuginfo || $1 == *-debugsource ]]
}

verify_no_debug_requirements() {
  local rpm_file=$1 requirement requirements
  requirements=$(rpm -qp --requires "$rpm_file") \
    || die "could not read requirements from $rpm_file"
  while read -r requirement _; do
    case $requirement in
      *-debuginfo|*-debuginfo\(*|*-debugsource|*-debugsource\(*)
        die "${rpm_file##*/} requires debug package $requirement"
        ;;
    esac
  done <<< "$requirements"
  return 0
}

declare -A upstream_sources=() expected_rpms=() mirror_rpms=() mirror_digests=()
while IFS=$'\t' read -r source name epoch version rpm_release arch input_digest extra \
  || [[ -n $source ]]; do
  [[ -n $source && -n $name && -n $epoch && -n $version && -n $rpm_release && -n $arch \
    && $input_digest =~ ^[0-9a-f]{64}$ && -z ${extra:-} ]] \
    || die "invalid upstream RPM identity in $upstream_manifest"
  is_debug_package "$name" && continue
  identity="$name"$'\t'"$epoch"$'\t'"$version"$'\t'"$rpm_release"$'\t'"$arch"
  [[ -z ${expected_rpms["$source|$identity"]+x} ]] \
    || die "duplicate expected upstream RPM identity for $source: $identity"
  upstream_sources[$source]=1
  expected_rpms["$source|$identity"]=$input_digest
done < "$upstream_manifest"

if [[ -n $mirror_input ]]; then
  shopt -s nullglob
  mirror_files=("$mirror"/*.rpm)
  reusable_mirror_files=()
  for rpm_file in "${mirror_files[@]}"; do
    identity=$(rpm -qp --qf '%{NAME}\t%{EPOCHNUM}\t%{VERSION}\t%{RELEASE}\t%{ARCH}' "$rpm_file") \
      || die "could not read mirrored RPM: $rpm_file"
    name=${identity%%$'\t'*}
    is_debug_package "$name" && continue
    [[ -z ${mirror_rpms[$identity]+x} ]] \
      || die "mirror has duplicate RPM identity: $identity"
    mirror_rpms[$identity]=$rpm_file
    reusable_mirror_files+=("$rpm_file")
  done
  mirror_files=("${reusable_mirror_files[@]}")
  mirror_manifest="$mirror/upstream-inputs.tsv"
  if [[ -f $mirror_manifest ]]; then
    while IFS=$'\t' read -r source name epoch version rpm_release arch input_digest extra \
      || [[ -n $source ]]; do
      [[ -n $source && -n $name && -n $epoch && -n $version && -n $rpm_release && -n $arch \
        && $input_digest =~ ^[0-9a-f]{64}$ && -z ${extra:-} ]] \
        || die "invalid published upstream input identity in $mirror_manifest"
      is_debug_package "$name" && continue
      identity="$name"$'\t'"$epoch"$'\t'"$version"$'\t'"$rpm_release"$'\t'"$arch"
      [[ -z ${mirror_digests[$identity]+x} ]] \
        || die "published input manifest has duplicate RPM identity: $identity"
      mirror_digests[$identity]=$input_digest
    done < "$mirror_manifest"
  fi
  # A reused package may depend on another Ryoku-built one (ryotunes needs the
  # Ryoku quickshell), so the probe below resolves against the mirror too.
  mirror_repo="$work/mirror-repo"
  mkdir -p "$mirror_repo"
  for rpm_file in "${mirror_files[@]}"; do
    ln -s "$rpm_file" "$mirror_repo/"
  done
  createrepo_c --quiet "$mirror_repo"
fi

signature_ok() {
  local rpm_file=$1 signature
  signature=$(rpmkeys --dbpath "$keydb" --checksig "$rpm_file" 2>&1) || return 1
  [[ $signature == *"signatures OK"* ]]
}

dependencies_resolve() {
  local rpm_file=$1 log_file="$work/dnf-assumeno.log" status
  set +e
  local -a mirror_args=()
  [[ -z $mirror_input ]] || mirror_args=(--repofrompath "ryoku-mirror,file://$mirror_repo"
    --setopt=ryoku-mirror.gpgcheck=0 --setopt=ryoku-mirror.repo_gpgcheck=0)
  LC_ALL=C dnf5 install --assumeno "${mirror_args[@]}" "$rpm_file" > "$log_file" 2>&1
  status=$?
  set -e
  if ((status == 0)) || grep -qF 'Operation aborted by the user.' "$log_file"; then
    return 0
  fi
  printf 'build-rpm-repo: dependency check rejected %s:\n' "${rpm_file##*/}" >&2
  cat "$log_file" >&2
  return 1
}

reuse_source() {
  local source=$1 key identity rpm_file expected_digest published_digest
  local -a candidates=()
  for key in "${!expected_rpms[@]}"; do
    [[ $key == "$source|"* ]] || continue
    identity=${key#"$source|"}
    expected_digest=${expected_rpms[$key]}
    published_digest=${mirror_digests[$identity]:-}
    if [[ $published_digest != "$expected_digest" ]]; then
      printf 'build-rpm-repo: %s published input digest is missing or changed for %s\n' \
        "$source" "$identity"
      return 1
    fi
    rpm_file=${mirror_rpms[$identity]:-}
    if [[ -z $rpm_file ]]; then
      printf 'build-rpm-repo: %s has no published RPM for %s\n' "$source" "$identity"
      return 1
    fi
    if ! signature_ok "$rpm_file"; then
      printf 'build-rpm-repo: %s has an untrusted published RPM: %s\n' \
        "$source" "${rpm_file##*/}"
      return 1
    fi
    if ! dependencies_resolve "$rpm_file"; then
      printf 'build-rpm-repo: %s published RPM is incompatible: %s\n' \
        "$source" "${rpm_file##*/}"
      return 1
    fi
    candidates+=("$rpm_file")
  done
  ((${#candidates[@]})) || die "$source has no expected binary RPM identities"
  for rpm_file in "${candidates[@]}"; do
    target="$out/${rpm_file##*/}"
    [[ ! -e $target ]] || die "duplicate RPM filename: ${target##*/}"
    cp "$rpm_file" "$target"
  done
  return 0
}

shopt -s nullglob
source_rpms=("$srpms"/*.src.rpm)
((${#source_rpms[@]})) || die "no source RPMs found in $srpms"
reused_sources=()
built_sources=()
for srpm in "${source_rpms[@]}"; do
  source=$(rpm -qp --qf '%{NAME}' "$srpm") || die "could not read SRPM: $srpm"
  if [[ -n $mirror_input && -n ${upstream_sources[$source]:-} ]] \
    && reuse_source "$source"; then
    reused_sources+=("$source")
    printf 'build-rpm-repo: Reused %s\n' "$source"
    continue
  fi
  rpmbuild --define "_buildhost ryoku-builder" \
    --define "use_source_date_epoch_as_buildtime 1" \
    --define "clamp_mtime_to_source_date_epoch 1" \
    --define "_topdir $work" --define "_rpmdir $work/RPMS" --rebuild "$srpm"
  built_sources+=("$source")
  printf 'build-rpm-repo: Built %s\n' "$source"
done

mapfile -d '' built_rpms < <(find "$work/RPMS" -type f -name '*.rpm' -print0)
built_targets=()
for rpm_file in "${built_rpms[@]}"; do
  name=$(rpm -qp --qf '%{NAME}' "$rpm_file") \
    || die "could not read built RPM: $rpm_file"
  if is_debug_package "$name"; then
    printf 'build-rpm-repo: Excluded %s\n' "${rpm_file##*/}"
    continue
  fi
  target="$out/${rpm_file##*/}"
  [[ ! -e $target ]] || die "duplicate RPM filename: ${target##*/}"
  cp "$rpm_file" "$target"
  built_targets+=("$target")
done

repo_rpms=("$out"/*.rpm)
((${#repo_rpms[@]})) || die 'no binary RPMs built or reused'
for rpm_file in "${repo_rpms[@]}"; do
  verify_no_debug_requirements "$rpm_file"
done
if [[ -n $signing_key ]]; then
  for rpm_file in "${built_targets[@]}"; do
    rpmsign --define "_gpg_name $signing_key" --addsign "$rpm_file"
    signature_ok "$rpm_file" \
      || die "signature verification failed: $rpm_file"
  done
  for rpm_file in "${repo_rpms[@]}"; do
    signature_ok "$rpm_file" \
      || die "repository contains an RPM without the release signature: $rpm_file"
  done
fi

printf 'build-rpm-repo: Reused upstream packages: %s\n' \
  "${reused_sources[*]:-(none)}"
printf 'build-rpm-repo: Built packages: %s\n' "${built_sources[*]:-(none)}"

cp "$upstream_manifest" "$out/upstream-inputs.tsv"

createrepo_c "$out"
if [[ -n $signing_key ]]; then
  gpg --batch --yes --local-user "$signing_key" --armor --detach-sign \
    "$out/repodata/repomd.xml"
  gpg --verify "$out/repodata/repomd.xml.asc" "$out/repodata/repomd.xml"
fi
cp "$srpms/release.json" "$out/release.json"
printf 'Built repository at %s\n' "$out"

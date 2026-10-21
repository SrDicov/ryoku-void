#!/usr/bin/env bash
set -euo pipefail

usage() {
	printf 'usage: %s REPO_ROOT DESTINATION\n' "${0##*/}" >&2
	exit 2
}

[[ $# -eq 2 ]] || usage
REPO_ROOT=$(cd "$1" && pwd -P)
DEST=$2
ARCH=${RYOKU_VOID_ISO_ARCH:-x86_64}
WORK=${RYOKU_VOID_ISO_OFFLINE_WORK:-${TMPDIR:-/tmp}/ryoku-void-offline-$UID}
VERIFY_ROOT=${RYOKU_VOID_ISO_VERIFY_ROOT:-$WORK}
KEYS_OUT=${RYOKU_VOID_ISO_KEYS_OUT:-$DEST/.keys}
RYOKU_REPO=${RYOKU_VOID_ISO_RYOKU_REPO:-}
VOID_MIRROR=${RYOKU_VOID_ISO_MIRROR:-https://repo-default.voidlinux.org/current}
ZREPO_RELEASE=${RYOKU_VOID_ISO_ZREPO:-https://api.github.com/repos/SrDicov/z-repo/releases/tags/stable}
RESOLVE=$REPO_ROOT/system/packages/resolve

log() { printf '\033[1;35m::\033[0m %s\n' "$*"; }
die() { printf 'offline-repo.sh: error: %s\n' "$*" >&2; exit 1; }

for command in xbps-install xbps-rindex awk du curl; do
	command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[[ -x $RESOLVE ]] || die "package resolver not found: $RESOLVE"
[[ -n $RYOKU_REPO ]] \
	|| die "RYOKU_VOID_ISO_RYOKU_REPO must name the built Ryoku XBPS repository"

normalize_repo() {
	local source=$1
	if [[ -d $source ]]; then
		source=$(cd "$source" && pwd -P)
		if [[ -s $source/$ARCH-repodata ]]; then
			printf '%s\n' "$source"
		elif [[ -s $source/$ARCH/$ARCH-repodata ]]; then
			printf '%s\n' "$source/$ARCH"
		else
			die "local Ryoku repository has no $ARCH-repodata: $source"
		fi
	else
		printf '%s\n' "${source%/}"
	fi
}
RYOKU_REPO=$(normalize_repo "$RYOKU_REPO")

rm -rf "$WORK" "$DEST" "$KEYS_OUT"
mkdir -p "$WORK/cache" "$DEST" "$KEYS_OUT"

seed_keys() {
	local root=$1
	mkdir -p "$root/var/db/xbps/keys"
	if compgen -G '/var/db/xbps/keys/*.plist' >/dev/null; then
		cp -a /var/db/xbps/keys/*.plist "$root/var/db/xbps/keys/"
	fi
	if [[ -n ${RYOKU_VOID_ISO_KEYRING_DIR:-} ]]; then
		compgen -G "$RYOKU_VOID_ISO_KEYRING_DIR/*.plist" >/dev/null \
			|| die "no key plist found in RYOKU_VOID_ISO_KEYRING_DIR=$RYOKU_VOID_ISO_KEYRING_DIR"
		cp -a "$RYOKU_VOID_ISO_KEYRING_DIR"/*.plist "$root/var/db/xbps/keys/"
	fi
	if compgen -G "$KEYS_OUT/*.plist" >/dev/null; then
		cp -a "$KEYS_OUT"/*.plist "$root/var/db/xbps/keys/"
	fi
}

# Trust anchors for every merged repository: the committed Ryoku keyring
# covers the upstream [ryoku] repository and the z-repo Hyprland lane.
RYOKU_KEYRING=${RYOKU_VOID_ISO_KEYRING_DIR:-$REPO_ROOT/void/packages/srcpkgs/ryoku-keyring/files}
compgen -G "$RYOKU_KEYRING"/*.plist >/dev/null \
	|| die "no XBPS key plists in $RYOKU_KEYRING"
cp -a "$RYOKU_KEYRING"/*.plist "$KEYS_OUT/"

repositories=(
	-R "$VOID_MIRROR"
	-R "$VOID_MIRROR/nonfree"
	-R "$VOID_MIRROR/multilib"
	-R "$VOID_MIRROR/multilib/nonfree"
	-R "$RYOKU_REPO"
)

# The Hyprland lane rides the third-party z-repo. Its packages bake into the
# offline repository, so the installer can install the Hyprland desktop from
# the image; their signatures verify against the committed z-repo key.
mapfile -t zrepo_packages < <(
	awk -F'\t' '$4 == "repo=zrepo" { print $2 }' \
		"$REPO_ROOT/void/packages/translations.tsv"
)
if ((${#zrepo_packages[@]})); then
	log "Fetching the Hyprland z-repo lane (${#zrepo_packages[@]} packages)"
	zrepo_work=$WORK/zrepo
	mkdir -p "$zrepo_work"
	assets=$(mktemp "$WORK/z-repo-assets.XXXXXX") \
		|| die "z-repo release asset list could not be written"
	curl -fsSL --retry 3 \
		-H 'Accept: application/vnd.github+json' \
		"$ZREPO_RELEASE" > "$assets"
	[[ -s $assets ]] || die "z-repo release at $ZREPO_RELEASE returned no asset list"
	zrepo_asset_url() {
		awk -v pkg="$1" '
			{
				if (match($0, /"browser_download_url"[[:space:]]*:[[:space:]]*"/)) {
					start = RSTART + RLENGTH
					quote = index(substr($0, start), "\"") + start - 1
					url = substr($0, start, quote - start)
					base = url
					sub(/.*\//, "", base)
					if (base ~ ("^" pkg "-[0-9]") && base ~ /\.xbps$/) {
						print url
						exit
					}
				}
			}' "$assets"
	}

	# The lane's own packages plus everything they require from the z-repo.
	# The Void mirror ships older hyprutils and lua55, so the library stack has
	# to come from the z-repo: otherwise the closure resolves the mirror's
	# versions, which cannot satisfy what the lane asks for.
	declare -A zrepo_have=()
	queue=("${zrepo_packages[@]}")
	while ((${#queue[@]})); do
		name=${queue[0]}
		queue=("${queue[@]:1}")
		[[ -n ${zrepo_have[$name]:-} ]] && continue
		url=$(zrepo_asset_url "$name")
		[[ -n $url ]] || die "z-repo release has no $name package archive"
		curl -fsSL --retry 3 -o "$zrepo_work/${url##*/}" "$url"
		curl -fsSL --retry 3 -o "$zrepo_work/${url##*/}.sig2" "$url.sig2"
		zrepo_have[$name]=1
		XBPS_TARGET_ARCH=$ARCH xbps-rindex --add "$zrepo_work/${url##*/}" >/dev/null
		while read -r dep; do
			[[ -n $dep ]] || continue
			need=${dep%%[<>=]*}
			[[ -n $need && $need != "$name" ]] || continue
			dep_url=$(zrepo_asset_url "$need")
			[[ -n $dep_url ]] || continue
			queue+=("$need")
		done < <(xbps-query --repository="$zrepo_work" -R -p run_depends "$name" 2>/dev/null)
	done
	rm -f "$assets"
	log "Hyprland lane: ${#zrepo_have[@]} packages from the z-repo"
	repositories+=(-R "$zrepo_work")
fi

mapfile -t target_packages < <(
	"$RESOLVE" \
		--table "$REPO_ROOT/void/packages/translations.tsv" \
		--lane system \
		--lane desktop \
		--lane dev \
		--lane hyprland \
		--lane hardware:amd \
		--lane hardware:intel \
		--lane hardware:nvidia \
		--lane hardware:vm \
		--session
)
target_packages+=(
	base-system linux linux-headers dracut limine
	void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree
	dolphin Thunar ryotunes ryomanager
)
mapfile -t target_packages < <(printf '%s\n' "${target_packages[@]}" | LC_ALL=C sort -u)

fetch_closure() {
	local name=$1
	shift
	local root=$WORK/root-$name attempt
	# ponytail: repo-default is not a snapshot and rotates between resolve and
	# download; the retry re-resolves against the live index, cheap because
	# $WORK/cache keeps every successfully downloaded .xbps. Five tries, 10 s
	# apart; escalate to SNAPSHOT_MIRROR=$VOID_MIRROR/@<date> only if this races.
	for attempt in 1 2 3 4 5; do
		rm -rf "$root"
		mkdir -p "$root"
		seed_keys "$root"
		log "Downloading $name closure ($# requested packages), attempt $attempt"
		if XBPS_ARCH=$ARCH xbps-install \
			-r "$root" -c "$WORK/cache" -i -S -D -y \
			"${repositories[@]}" "$@"
		then
			return 0
		fi
		if ((attempt == 5)); then
			die "$name closure download failed after 5 attempts; last xbps-install error above"
		fi
		log "$name closure attempt $attempt failed: the Void mirror rotates package versions between resolve and download; retrying with a fresh resolve"
		sleep 10
	done
}

fetch_closure target "${target_packages[@]}"

# Fetch conflicting NVIDIA branches through separate roots into the shared cache.
nvidia_branches=(
	'nvidia nvidia-libs-32bit'
	'nvidia580 nvidia580-libs-32bit'
	'nvidia470 nvidia470-libs-32bit'
	'nvidia390 nvidia390-libs-32bit'
)
for branch in "${nvidia_branches[@]}"; do
	read -r -a packages <<< "$branch"
	fetch_closure "${packages[0]}" linux-headers "${packages[@]}"
done

shopt -s nullglob

link_or_copy_files() {
	local source
	for source in "$@"; do
		cp -al -- "$source" "$DEST/" 2>/dev/null \
			|| cp -a -- "$source" "$DEST/"
	done
}

cache_files=("$WORK/cache"/*.xbps "$WORK/cache"/*.xbps.sig2)
cache_archives=("$WORK/cache"/*.xbps)
((${#cache_archives[@]})) || die "XBPS downloaded no package archives"
link_or_copy_files "${cache_files[@]}"

# XBPS reads local repositories in place, so their packages never enter cache.
if [[ -d $RYOKU_REPO ]]; then
	local_files=("$RYOKU_REPO"/*.xbps "$RYOKU_REPO"/*.xbps.sig2)
	local_archives=("$RYOKU_REPO"/*.xbps)
	((${#local_archives[@]})) || die "local Ryoku repository has no package archives"
	link_or_copy_files "${local_files[@]}"
fi

if ((${#zrepo_packages[@]})); then
	zrepo_files=("$zrepo_work"/*.xbps "$zrepo_work"/*.xbps.sig2)
	((${#zrepo_files[@]})) || die "z-repo lane fetched no package archives"
	link_or_copy_files "${zrepo_files[@]}"
fi

packages=("$DEST"/*.xbps)
log "Indexing ${#packages[@]} package archives"
XBPS_TARGET_ARCH=$ARCH xbps-rindex --add "${packages[@]}"
XBPS_TARGET_ARCH=$ARCH xbps-rindex --remove-obsoletes "$DEST"
XBPS_TARGET_ARCH=$ARCH xbps-rindex --hashcheck --clean "$DEST"
[[ -s $DEST/$ARCH-repodata ]] || die "$ARCH-repodata was not created"
concrete_headers=("$DEST"/linux[0-9]*-headers-*.xbps)
((${#concrete_headers[@]})) \
	|| die "offline closure has linux-headers but no concrete kernel-series headers"

# XBPS checks root free space even for dry runs that write almost nothing.
verify_closure() {
	local name=$1
	shift
	local root=$VERIFY_ROOT/verify-$name
	mkdir -p "$root"
	seed_keys "$root"
	XBPS_ARCH=$ARCH xbps-install -r "$root" -i -R "$DEST" -Sny "$@" >/dev/null
}
verify_closure target "${target_packages[@]}"
for branch in "${nvidia_branches[@]}"; do
	read -r -a packages <<< "$branch"
	verify_closure "${packages[0]}" linux-headers "${packages[@]}"
done

size=$(du -sh "$DEST" | awk '{print $1}')
log "Offline repository ready at $DEST ($size)"

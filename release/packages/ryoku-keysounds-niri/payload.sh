#!/usr/bin/env bash
set -euo pipefail

: "${RYOKU_SRC:?set RYOKU_SRC to the checkout root}"
: "${RYOKU_PKGVER:?set RYOKU_PKGVER to the package version}"
: "${RYOKU_BUILD_DIR:?set RYOKU_BUILD_DIR to the build directory}"

_repo=$RYOKU_SRC

stage_prebuilt() {
  [[ -n ${RYOKU_PREBUILT_DIR:-} ]] || return 1
  mkdir -p "$RYOKU_BUILD_DIR"
  cp -a "$RYOKU_PREBUILT_DIR/." "$RYOKU_BUILD_DIR/"
}

# The engine niri gets in place of the Hyprland plugin: a single Rust file with
# no crate tree, built with rustc alone and linked against libcanberra.
case "${1:-}" in
build)
  stage_prebuilt && exit 0
  mkdir -p "$RYOKU_BUILD_DIR"
  rustc -O --edition 2021 -C strip=symbols \
    "$_repo/ryoku/keysounds/main.rs" -o "$RYOKU_BUILD_DIR/ryoku-keysounds"
  ;;
install)
  pkgdir=${2:?install requires a destination root}
  install -Dm755 "$RYOKU_BUILD_DIR/ryoku-keysounds" "$pkgdir/usr/bin/ryoku-keysounds"
  ;;
*)
  printf 'usage: %s <build|install DESTDIR>\n' "$0" >&2
  exit 2
  ;;
esac

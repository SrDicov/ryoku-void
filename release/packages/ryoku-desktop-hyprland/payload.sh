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

install_payload() {
  local cfg="$pkgdir/usr/share/ryoku/config"
  local script

  # The whole tree includes the hardware-managed drop-ins and the compositor's
  # leaf scripts. A package update must move them as one config generation.
  install -d "$cfg/hypr"
  cp -a "$_repo/ryoku/hyprland/." "$cfg/hypr/"

  install -Dm644 "$_repo/ryoku/hyprland/hyprland-portals.conf" \
    "$cfg/xdg-desktop-portal/hyprland-portals.conf"
  install -Dm644 "$_repo/ryoku/apps/hyprland-preview-share-picker/config.yaml" \
    "$cfg/hyprland-preview-share-picker/config.yaml"
  chmod -R u=rwX,go=rX "$pkgdir/usr/share/ryoku"

  for script in "$_repo"/ryoku/hyprland/scripts/ryoku-*; do
    [[ -f $script ]] || continue
    install -Dm755 "$script" "$pkgdir/usr/bin/${script##*/}"
  done

  install -Dm755 "$RYOKU_BUILD_DIR/ryoku-wm-hyprland" \
    "$pkgdir/usr/bin/ryoku-wm-hyprland"
  install -d "$pkgdir/usr/lib/qt6/qml/Ryoku/Wm/Hyprland"
  cp -a "$_repo/ryoku/wm/hyprland/qml/." \
    "$pkgdir/usr/lib/qt6/qml/Ryoku/Wm/Hyprland/"
}

case "${1:-}" in
build)
  stage_prebuilt && exit 0
  mkdir -p "$RYOKU_BUILD_DIR"
  cd "$_repo/ryoku/wm/hyprland"
  go build -mod=vendor -o "$RYOKU_BUILD_DIR/ryoku-wm-hyprland" .
  ;;
  install)
    pkgdir=${2:?install requires a destination root}
    RYOKU_INIT_MODE=${3:?install requires systemd or runit}
    case "$RYOKU_INIT_MODE" in
      systemd|runit) ;;
      *) printf 'unsupported init mode: %s\n' "$RYOKU_INIT_MODE" >&2; exit 2 ;;
    esac
    install_payload
    ;;
  *)
    printf 'usage: %s <build|install DESTDIR systemd|runit>\n' "$0" >&2
    exit 2
    ;;
esac

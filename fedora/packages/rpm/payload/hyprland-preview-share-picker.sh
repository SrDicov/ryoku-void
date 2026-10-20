# shellcheck shell=bash
: "${startdir:?}" "${srcdir:?}" "${pkgdir:?}"
_repo="$startdir/../../../.."

build() {
  local source="$_repo/.rpm-hyprland-preview-share-picker/hyprland-preview-share-picker"
  (
    cd "$source" || exit
    CARGO_TARGET_DIR="$srcdir/target" cargo build --offline --locked --release
  )
  "$srcdir/target/release/hyprland-preview-share-picker" schema > "$srcdir/schema.json"
}

package() {
  local source="$_repo/.rpm-hyprland-preview-share-picker/hyprland-preview-share-picker"
  install -Dm755 "$srcdir/target/release/hyprland-preview-share-picker" \
    "$pkgdir/usr/bin/hyprland-preview-share-picker"
  install -Dm644 "$srcdir/schema.json" \
    "$pkgdir/usr/share/hyprland-preview-share-picker/schema.json"
  install -Dm644 "$source/LICENSE" \
    "$pkgdir/usr/share/licenses/hyprland-preview-share-picker/LICENSE"
}

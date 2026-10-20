#!/usr/bin/env bash
set -euo pipefail

recipe=$RYOKU_FETCH_TREE/release/packages/ryoku-cursor-material
install -Dpm 0644 "$recipe/themes.json" "$RYOKU_FETCH_SOURCES/themes.json"
install -Dpm 0755 "$recipe/compile_bibata_material.fish" \
  "$RYOKU_FETCH_SOURCES/compile_bibata_material.fish"
install -Dpm 0755 "$recipe/metadata_generator.py" \
  "$RYOKU_FETCH_SOURCES/metadata_generator.py"
install -Dpm 0755 "$recipe/ryoku-cursor-material-recolor" \
  "$RYOKU_FETCH_SOURCES/ryoku-cursor-material-recolor"

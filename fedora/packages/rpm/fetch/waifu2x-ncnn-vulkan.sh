#!/usr/bin/env bash
set -euo pipefail

sources=${RYOKU_FETCH_SOURCES:?RYOKU_FETCH_SOURCES is required}
cat > "$sources/waifu2x-ncnn-vulkan-wrapper" <<'WRAPPER'
#!/bin/sh
for arg do
  if [ "$arg" = "-m" ]; then
    exec /usr/libexec/waifu2x-ncnn-vulkan.real "$@"
  fi
done
exec /usr/libexec/waifu2x-ncnn-vulkan.real \
  -m /usr/share/waifu2x-ncnn-vulkan/models-cunet "$@"
WRAPPER
chmod 0755 "$sources/waifu2x-ncnn-vulkan-wrapper"

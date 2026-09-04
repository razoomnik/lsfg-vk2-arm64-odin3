#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$ROOT/.build-v3}"
SRC="$WORK/lsfg-vk"
BUILD="$WORK/build"
STAGE="$WORK/stage"
BUNDLE="$ROOT/plugin/bin/arm64-v3"
RELEASES="$ROOT/releases"
ZIP="$RELEASES/LSFG-VK-3-ARM64-Odin3.zip"
UPSTREAM_URL="${LSFGVK_UPSTREAM_URL:-https://git.lsfg-vk.dev/lsfg-vk.git}"
UPSTREAM_REF="${LSFGVK_UPSTREAM_REF:-master}"

rm -rf "$WORK" "$BUNDLE"
mkdir -p "$WORK" "$BUNDLE" "$RELEASES"

echo "== Clone official lsfg-vk upstream =="
git clone --filter=blob:none "$UPSTREAM_URL" "$SRC"
git -C "$SRC" checkout "$UPSTREAM_REF"
UPSTREAM_SHA="$(git -C "$SRC" rev-parse HEAD)"
UPSTREAM_DATE="$(git -C "$SRC" show -s --format=%cI HEAD)"

echo "Upstream: $UPSTREAM_SHA ($UPSTREAM_DATE)"

echo "== Configure native AArch64 build =="
MACHINE="$(uname -m)"
if [[ "$MACHINE" != "aarch64" && "$MACHINE" != "arm64" ]]; then
  echo "ERROR: v3 must be built natively on AArch64; got $MACHINE" >&2
  exit 2
fi

# Current upstream uses LSFGVK_BUILD_LAYER.  Older v2 snapshots used
# LSFGVK_BUILD_VK_LAYER, so set both: CMake harmlessly ignores an unused cache
# variable. UI stays off; CLI is built for diagnostics/benchmarking.
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$STAGE" \
  -DLSFGVK_BUILD_LAYER=ON \
  -DLSFGVK_BUILD_VK_LAYER=ON \
  -DLSFGVK_BUILD_UI=OFF \
  -DLSFGVK_BUILD_CLI=ON \
  -DLSFGVK_INSTALL_XDG_FILES=OFF

cmake --build "$BUILD" --parallel "$(nproc)"
cmake --install "$BUILD" || true

echo "== Locate built files =="
find_first() {
  local pattern="$1"
  find "$STAGE" "$BUILD" -type f -name "$pattern" -print -quit 2>/dev/null || true
}

LAYER="$(find_first 'liblsfg-vk-layer.so')"
CLI="$(find_first 'lsfg-vk-cli')"
MANIFEST="$(find_first 'VkLayer_LSFGVK_frame_generation.json')"

if [[ -z "$LAYER" || ! -f "$LAYER" ]]; then
  echo "ERROR: liblsfg-vk-layer.so not found" >&2
  find "$BUILD" -maxdepth 4 -type f | sort >&2
  exit 3
fi

if [[ -z "$MANIFEST" || ! -f "$MANIFEST" ]]; then
  TEMPLATE="$(find "$SRC" -type f -name 'VkLayer_LSFGVK_frame_generation.json.in' -print -quit)"
  if [[ -z "$TEMPLATE" ]]; then
    echo "ERROR: Vulkan manifest not found" >&2
    exit 4
  fi
  # Generate a private manifest ourselves. The plugin installer rewrites the
  # absolute library_path after installation, so the bundle stays relocatable.
  cat > "$BUNDLE/VkLayer_LSFGVK_frame_generation.json" <<'JSON'
{
  "file_format_version": "1.0.0",
  "layer": {
    "name": "VK_LAYER_LSFGVK_frame_generation",
    "type": "GLOBAL",
    "library_path": "liblsfg-vk-layer.so",
    "api_version": "1.3.0",
    "implementation_version": "1",
    "description": "LSFG-VK frame generation (Odin 3 v3 ARM64)",
    "disable_environment": { "DISABLE_LSFGVK": "1" }
  }
}
JSON
else
  cp -f "$MANIFEST" "$BUNDLE/VkLayer_LSFGVK_frame_generation.json"
fi

cp -f "$LAYER" "$BUNDLE/liblsfg-vk-layer.so"
chmod 0755 "$BUNDLE/liblsfg-vk-layer.so"
if [[ -n "$CLI" && -f "$CLI" ]]; then
  cp -f "$CLI" "$BUNDLE/lsfg-vk-cli"
  chmod 0755 "$BUNDLE/lsfg-vk-cli"
fi

cat > "$BUNDLE/UPSTREAM_BUILD_INFO.txt" <<EOF
variant=LSFG-VK-3-ARM64-Odin3
upstream_url=$UPSTREAM_URL
upstream_ref=$UPSTREAM_REF
upstream_commit=$UPSTREAM_SHA
upstream_commit_date=$UPSTREAM_DATE
build_arch=$(uname -m)
build_os=$(uname -s)
EOF

file "$BUNDLE/liblsfg-vk-layer.so"
readelf -h "$BUNDLE/liblsfg-vk-layer.so" | grep -E 'Machine:.*AArch64'

echo "== Assemble Decky v3 ZIP =="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/decky-lsfg-vk3-arm64"
cp -a "$ROOT/plugin/." "$TMP/decky-lsfg-vk3-arm64/"
find "$TMP" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$TMP" -type f -name '*.pyc' -delete
rm -f "$ZIP" "$ZIP.sha256"
(
  cd "$TMP"
  zip -qr "$ZIP" decky-lsfg-vk3-arm64
)
sha256sum "$ZIP" > "$ZIP.sha256"

echo "Built: $ZIP"
cat "$ZIP.sha256"

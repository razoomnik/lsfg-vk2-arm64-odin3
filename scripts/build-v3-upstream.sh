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

# Current upstream uses LSFGVK_BUILD_LAYER. Older v2 snapshots used
# LSFGVK_BUILD_VK_LAYER, so set both. UI stays off; CLI is optional.
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
  find "$BUILD" -maxdepth 5 -type f | sort >&2
  exit 3
fi

if [[ -n "$MANIFEST" && -f "$MANIFEST" ]]; then
  cp -f "$MANIFEST" "$BUNDLE/VkLayer_LSFGVK_frame_generation.json"
else
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

echo "== Assemble parallel Decky v3 package =="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PKG="$TMP/decky-lsfg-vk3-arm64"
mkdir -p "$PKG"
cp -a "$ROOT/plugin/." "$PKG/"

# Reuse the proven installer slot name inside the package, but replace its
# payload with the freshly built official-upstream AArch64 layer.
rm -rf "$PKG/bin/arm64-hot1x"
mkdir -p "$PKG/bin/arm64-hot1x"
cp -a "$BUNDLE/." "$PKG/bin/arm64-hot1x/"

# Transform only the generated v3 package. The checked-in v2 source and every
# installed v2 path remain untouched. This is what makes rollback a one-digit
# edit in Steam: lsfg-vk2-arm64 <-> lsfg-vk3-arm64.
python3 - "$PKG" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
replacements = [
    ("decky-lsfg-vk2-arm64", "decky-lsfg-vk3-arm64"),
    ("lsfg-vk2-arm64", "lsfg-vk3-arm64"),
    ("LSFG-VK 2 ARM64", "LSFG-VK 3 ARM64"),
    ("lsfg-vk 2 ARM64", "lsfg-vk 3 ARM64"),
    ("LSFG-VK 2 ARM64 Hot-1X", "LSFG-VK 3 ARM64 upstream"),
]

for path in root.rglob("*"):
    if not path.is_file() or path.suffix in {".so", ".png", ".jpg", ".jpeg", ".zip"}:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    new = text
    for old, repl in replacements:
        new = new.replace(old, repl)
    if new != text:
        path.write_text(new, encoding="utf-8")

configuration = root / "py_modules/lsfg_vk/configuration.py"
with configuration.open("a", encoding="utf-8") as fh:
    fh.write("\n# v3 package-only official-upstream bridge\n")
    fh.write("from .v3_bridge import apply_v3_bridge as _apply_v3_bridge\n")
    fh.write("_apply_v3_bridge(ConfigurationService, ConfigurationManager, DEFAULT_PROFILE_NAME)\n")

manifest = root / "plugin.json"
text = manifest.read_text(encoding="utf-8")
text = text.replace(
    "Self-contained patched lsfg-vk 2.0-dev28 for AYN Odin 3 / Armada ARM64 with live 1X passthrough and 2X-4X frame generation.",
    "Native AArch64 build of current official lsfg-vk v2+ upstream for AYN Odin 3 / Armada, packaged as parallel v3 with one-digit rollback to v2."
)
manifest.write_text(text, encoding="utf-8")
PY

find "$PKG" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$PKG" -type f -name '*.pyc' -delete

# Sanity-check package identity and the exact launch option before zipping.
grep -q 'LSFG-VK 3 ARM64' "$PKG/plugin.json"
grep -q 'lsfg-vk3-arm64 %command%' "$PKG/py_modules/lsfg_vk/plugin.py"
grep -q 'decky-lsfg-vk3-arm64' "$PKG/py_modules/lsfg_vk/constants.py"
grep -q 'apply_v3_bridge' "$PKG/py_modules/lsfg_vk/configuration.py"
readelf -h "$PKG/bin/arm64-hot1x/liblsfg-vk-layer.so" | grep -E 'Machine:.*AArch64'

rm -f "$ZIP" "$ZIP.sha256"
(
  cd "$TMP"
  zip -qr "$ZIP" decky-lsfg-vk3-arm64
)
sha256sum "$ZIP" > "$ZIP.sha256"

echo "Built: $ZIP"
cat "$ZIP.sha256"

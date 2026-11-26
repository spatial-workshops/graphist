#!/usr/bin/env bash
# Builds build/Graphist.app from the command line (no Xcode project needed).
#
# Environment variables:
#   CONFIG=release|debug        Swift build configuration (default: release)
#   UNIVERSAL=1                 Build arm64 + x86_64 (default: host arch only)
#   BUNDLE_ID=com.you.graphist  CFBundleIdentifier (default: from Packaging/Info.plist)
#   VERSION=1.2.0               CFBundleShortVersionString (default: from Info.plist)
#   BUILD_NUMBER=42             CFBundleVersion (default: git commit count)
#   SHADERS=auto|metallib|source
#        auto     precompile shaders to Graphist.metallib if the Metal toolchain is
#                 installed, otherwise bundle the .metal sources (compiled at launch)
#        metallib require precompilation (fail if the toolchain is missing)
#        source   always bundle sources
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Graphist"
CONFIG="${CONFIG:-release}"
UNIVERSAL="${UNIVERSAL:-0}"
SHADERS="${SHADERS:-auto}"
OUT_DIR="$ROOT/build"
APP="$OUT_DIR/$APP_NAME.app"
SHADER_SRC="$ROOT/Shaders"

ARCH_ARGS=()
if [[ "$UNIVERSAL" == "1" ]]; then
  ARCH_ARGS=(--arch arm64 --arch x86_64)
fi

# ---------------------------------------------------------------------------
echo "==> Building Swift sources ($CONFIG${ARCH_ARGS[@]+, universal})"
swift build -c "$CONFIG" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)"

# ---------------------------------------------------------------------------
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
printf 'APPL????' > "$APP/Contents/PkgInfo"

PLIST="$APP/Contents/Info.plist"
cp "$ROOT/Packaging/Info.plist" "$PLIST"
[[ -n "${BUNDLE_ID:-}" ]] && plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
[[ -n "${VERSION:-}" ]] && plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$PLIST"

if [[ -f "$ROOT/Packaging/AppIcon.icns" ]]; then
  cp "$ROOT/Packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  plutil -replace CFBundleIconFile -string "AppIcon" "$PLIST"
fi

# ---------------------------------------------------------------------------
metal_toolchain_available() {
  xcrun -sdk macosx metal --version >/dev/null 2>&1
}

compile_metallib() {
  local air_dir="$OUT_DIR/shaders-air"
  rm -rf "$air_dir"
  mkdir -p "$air_dir"

  # Every directory that contains a header is on the include path.
  local include_flags=()
  local dir
  while IFS= read -r dir; do
    include_flags+=(-I "$dir")
  done < <(find "$SHADER_SRC" -name '*.h' -exec dirname {} \; | sort -u)

  local debug_flags=()
  if [[ "$CONFIG" == "debug" ]]; then
    debug_flags=(-gline-tables-only -frecord-sources) # enables shader debugging in GPU captures
  fi

  local airs=()
  local src rel air
  while IFS= read -r -d '' src; do
    rel="${src#"$SHADER_SRC"/}"
    air="$air_dir/${rel//\//_}.air"
    echo "    metal $rel"
    xcrun -sdk macosx metal -c "$src" -o "$air" \
      ${include_flags[@]+"${include_flags[@]}"} ${debug_flags[@]+"${debug_flags[@]}"}
    airs+=("$air")
  done < <(find "$SHADER_SRC" -name '*.metal' -print0 | sort -z)

  xcrun -sdk macosx metallib "${airs[@]}" -o "$APP/Contents/Resources/$APP_NAME.metallib"
}

bundle_shader_sources() {
  cp -R "$SHADER_SRC" "$APP/Contents/Resources/Shaders"
}

case "$SHADERS" in
  source)
    echo "==> Bundling shader sources (compiled at launch)"
    bundle_shader_sources
    ;;
  metallib|auto)
    if metal_toolchain_available; then
      echo "==> Compiling shaders to $APP_NAME.metallib"
      compile_metallib
    elif [[ "$SHADERS" == "metallib" ]]; then
      echo "error: Metal toolchain not found. Install it with:" >&2
      echo "       xcodebuild -downloadComponent MetalToolchain" >&2
      exit 1
    else
      echo "warning: Metal toolchain not found; bundling shader sources instead." >&2
      echo "         Install it with: xcodebuild -downloadComponent MetalToolchain" >&2
      bundle_shader_sources
    fi
    ;;
  *)
    echo "error: SHADERS must be auto, metallib or source" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Ad-hoc signature so the bundle runs locally (Apple silicon requires a signature).
# Use scripts/sign-and-notarize.sh for a distributable Developer ID signature.
echo "==> Ad-hoc signing"
codesign --force --sign - "$APP"

echo "==> Done: $APP"
echo "    open \"$APP\""

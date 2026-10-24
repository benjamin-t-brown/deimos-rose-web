#!/usr/bin/env bash
# Build Deimos Rose for the web: Odin -> WASM object file, then link with
# emscripten against raylib's web build.
#
# Prerequisites:
#   - Odin dev-2026-09 or later (with vendor:raylib and WASM target support)
#   - Emscripten SDK (emsdk) activated in the shell
#
# Usage:
#   ./build_web.sh [EMSCRIPTEN_SDK_DIR]
#
# If EMSCRIPTEN_SDK_DIR is provided, sources emsdk_env.sh from there.
# Otherwise assumes emcc is already in PATH.

set -euo pipefail

# Point this to where you installed emscripten, or leave unset if emcc is
# already in PATH.
EMSCRIPTEN_SDK_DIR="${1:-${EMSCRIPTEN_SDK_DIR:-}}"
OUT_DIR="build/web"

cd "$(dirname "$0")"

mkdir -p "$OUT_DIR"

# Source emscripten if a directory was provided
if [ -n "$EMSCRIPTEN_SDK_DIR" ] && [ -f "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh" ]; then
	export EMSDK_QUIET=1
	# shellcheck disable=SC1091
	. "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh"
fi

# Check emcc is available
if ! command -v emcc >/dev/null 2>&1; then
	echo "Error: emcc not found. Install emsdk or set EMSCRIPTEN_SDK_DIR." >&2
	echo "  https://emscripten.org/docs/getting_started/downloads.html" >&2
	exit 1
fi

# Check odin is available
if ! command -v odin >/dev/null 2>&1; then
	echo "Error: odin not found. Install Odin dev-2026-09 or later." >&2
	exit 1
fi

echo "Building Deimos Rose for web..."
echo "  Odin: $(odin version)"
echo "  emcc: $(emcc --version | head -1)"

# Odin dev-2026-09's core:os panics on js ("unsupported"), and filepath.glob
# is compiled out there. web/odin_os replaces the panic and the file,
# directory and stat backends with ones that call web/fs_em.c, which uses
# emscripten's libc and so sees the preloaded files. The compiler install is
# restored when this script exits, including on failure.
ODIN_PATH=$(odin root)
OS_DIR="$ODIN_PATH/core/os"
RT_DIR="$ODIN_PATH/base/runtime"
OS_BACKUP=$(mktemp -d)
OS_FILES="wasm.odin file_js.odin dir_js.odin stat_js.odin heap_js.odin"
for f in $OS_FILES; do
	cp "$OS_DIR/$f" "$OS_BACKUP/$f"
	cp "web/odin_os/$f" "$OS_DIR/$f"
done
# The default wasm allocator grows memory itself. Point it at emscripten's
# malloc for this compile, and remove the added file afterwards.
cp "$RT_DIR/default_allocators_general.odin" "$OS_BACKUP/default_allocators_general.odin"
cp "web/odin_runtime/default_allocators_general.odin" "$RT_DIR/default_allocators_general.odin"
cp "web/odin_runtime/emscripten_heap.odin" "$RT_DIR/emscripten_heap.odin"
FS=$(mktemp -d)
cleanup() {
	rm -rf "$FS"
	for f in $OS_FILES; do
		cp "$OS_BACKUP/$f" "$OS_DIR/$f"
	done
	cp "$OS_BACKUP/default_allocators_general.odin" "$RT_DIR/default_allocators_general.odin"
	rm -f "$RT_DIR/emscripten_heap.odin"
	rm -rf "$OS_BACKUP"
}
trap cleanup EXIT

# Build the static game (all plugins except netplay) to WASM object file.
# RAYLIB_WASM_LIB=env.o tells vendor:raylib to use env.o (emscripten's
# internal object), which emcc will populate with the real raylib.
odin build game_web \
	-target:js_wasm32 \
	-build-mode:obj \
	-collection:dr=. \
	-define:RAYLIB_WASM_LIB=env.o \
	-define:RAYGUI_WASM_LIB=env.o \
	-define:DR_VERSION="$(bash tools/version/version.sh)" \
	-vet -strict-style \
	-out:"$OUT_DIR/deimos.wasm.obj"

# Copy odin.js (Odin's WASM runtime) to output
cp "$ODIN_PATH/core/sys/wasm/js/odin.js" "$OUT_DIR/"

# Files to link: our WASM object, the filesystem helpers, raylib's web build, raygui
files="$OUT_DIR/deimos.wasm.obj"
files="$files web/fs_em.c"
files="$files $ODIN_PATH/vendor/raylib/wasm/libraylib.web.a"
files="$files $ODIN_PATH/vendor/raylib/wasm/libraygui.a"

# emcc flags:
#  -sEXPORTED_RUNTIME_METHODS: expose HEAPF32 for Odin
#  -sUSE_GLFW=3: raylib uses GLFW
#  -sWARN_ON_UNDEFINED_SYMBOLS=0: some Odin symbols stay undefined
#  -sASSERTIONS: helpful error messages
#  -sALLOW_MEMORY_GROWTH=1: let memory grow past the initial heap
#  -sINITIAL_MEMORY=512MB: the packed data is copied into this heap
#  -sSTACK_SIZE=16MB: JSON records and the startup walk exceed 2MB
#  --shell-file: use our HTML template
#  --preload-file: bundle assets and plugin content into the build
# FS and IDBFS are what the page mounts at /persist (IndexedDB). HEAPU8 is
# how a save file is copied out for download and back in for upload.
flags="-sEXPORTED_RUNTIME_METHODS=['HEAPF32','HEAPU8','FS','IDBFS']"
flags="$flags -lidbfs.js"
flags="$flags -sUSE_GLFW=3"
flags="$flags -sWARN_ON_UNDEFINED_SYMBOLS=0"
flags="$flags -sASSERTIONS"
# The preloaded data (assets plus plugin content, ~180 MB without Recovered
# Levels) is copied into wasm memory at startup. 512 MB leaves room for that
# and the heap; growth covers anything past it. 512 MiB is a multiple of the
# wasm page size.
flags="$flags -sALLOW_MEMORY_GROWTH=1"
flags="$flags -sINITIAL_MEMORY=536870912"  # 512MB
# JSON files and the startup walk need more than the 2 MB default.
# The largest unit record is ~230 KB and the parser is recursive.
flags="$flags -sSTACK_SIZE=16777216"       # 16MB
flags="$flags --shell-file game_web/index_template.html"

# Stage the virtual filesystem outside the output directory, so the copy is
# not published next to index.html. Recovered Levels is left out: its maps
# are ~90 MB and the campaign is optional. Netplay is not in this build.
if [ -d "assets" ]; then
	cp -a assets "$FS/assets"
	mkdir -p "$FS/plugins"
	for dir in plugins/*/; do
		[ -d "$dir" ] || continue
		name=$(basename "$dir")
		case "$name" in
			recovered_levels|netplay) continue ;;
		esac
		cp -a "$dir" "$FS/plugins/$name"
	done
	flags="$flags --preload-file $FS/assets@/assets --preload-file $FS/plugins@/plugins"
else
	echo "Warning: assets/ not found. The game will not have any content."
	echo "  Run 'mise run assets:all' to extract assets from the original game."
fi

# For debugging: add -g for better stack traces in Chrome
# flags="$flags -g"

# shellcheck disable=SC2086
emcc -o "$OUT_DIR/index.html" $files $flags

rm -f "$OUT_DIR/deimos.wasm.obj"
touch "$OUT_DIR/.nojekyll"

echo ""
echo "Web build created in $OUT_DIR"
echo ""
echo "To test locally:"
echo "  cd $OUT_DIR && python3 -m http.server 8000"
echo "  Then open http://localhost:8000 in your browser"
echo ""
echo "Note: You cannot open index.html directly due to CORS policy."

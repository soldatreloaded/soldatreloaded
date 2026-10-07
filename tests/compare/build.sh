#!/usr/bin/env bash
# Builds the C game's simulation, at a pinned commit, into build/reference.lib: the
# reference the Odin port is compared against. Needs a checkout of the C game (by
# default beside this one, at ../bettersoldat; else set BETTERSOLDAT), clang, and the
# source of the miniz the C game reads packed maps with: by default the archive xmake
# fetched when it built the C game; else set MINIZ_SOURCE to a miniz-*.tar.gz. miniz is
# built here too, so the whole reference links against the C runtime Odin uses.
#
#   tests/compare/build.sh
#   odin run tests/compare
set -euo pipefail

REFERENCE_COMMIT=74fee85 # the C game's apps/shared as the port follows it

here="$(cd "$(dirname "$0")" && pwd)"
source="${BETTERSOLDAT:-$here/../../../bettersoldat}"
build="$here/build"
shared="$build/source/apps/shared"

miniz_source="${MINIZ_SOURCE:-}"
if [ -z "$miniz_source" ]; then
	for found in "$LOCALAPPDATA"/.xmake/cache/packages/*/m/miniz/*/miniz-*.tar.gz; do
		if [ -f "$found" ]; then miniz_source="$found"; fi
	done
fi
if [ -z "$miniz_source" ] || [ ! -f "$miniz_source" ]; then
	echo "no miniz source: build the C game once with xmake, or set MINIZ_SOURCE" >&2
	exit 1
fi

rm -rf "$build"
mkdir -p "$build/source" "$build/objects" "$build/miniz"
git -C "$source" archive "$REFERENCE_COMMIT" apps/shared assets/data | tar -x -C "$build/source" # its code, and the data it plays by
(cd "$(dirname "$miniz_source")" && tar -xzf "$(basename "$miniz_source")" -C "$build/miniz" --strip-components=1)
# what miniz's own build generates: nothing to export from a static library
printf '#pragma once\n#define MINIZ_EXPORT\n' > "$build/miniz/miniz_export.h"
mkdir -p "$build/include/miniz" && cp "$build/miniz"/*.h "$build/include/miniz/"

# Floats exactly as written, with no fused multiply-adds, so both games round the same.
for file in "$shared"/game/*.c "$shared"/game/systems/*.c "$shared"/resources/*.c "$shared"/utils/*.c "$here/reference.c"; do
	clang -c -O2 -std=c11 -ffp-contract=off -D_CRT_SECURE_NO_WARNINGS -Wno-deprecated-declarations \
		-I "$shared" -I "$build/include/miniz" "$file" -o "$build/objects/$(basename "${file%.c}").o"
done
for file in "$build"/miniz/miniz*.c; do
	clang -c -O2 -D_CRT_SECURE_NO_WARNINGS -Wno-deprecated-declarations -I "$build/miniz" \
		"$file" -o "$build/objects/$(basename "${file%.c}").o"
done
llvm-lib -out:"$build/reference.lib" "$build"/objects/*.o

echo "built $build/reference.lib from the C game at $REFERENCE_COMMIT"

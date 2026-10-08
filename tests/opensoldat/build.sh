#!/usr/bin/env bash
# Builds OpenSoldat's simulation, at a pinned commit, into build/reference.dll: the
# reference the port is compared against here. Needs a checkout of OpenSoldat (by default
# beside this one, at ../opensoldat; else set OPENSOLDAT) and Free Pascal 3.2.2 with its
# x86_64-win64 cross compiler (by default under C:/FPC/3.2.2; else set FPC).
#
#   tests/opensoldat/build.sh
#   odin run tests/opensoldat
set -euo pipefail

REFERENCE_COMMIT=c7596cd # OpenSoldat's master as the comparison was made against it

here="$(cd "$(dirname "$0")" && (pwd -W 2>/dev/null || pwd))" # Windows' form: Free Pascal reads no other
source="${OPENSOLDAT:-$here/../../../opensoldat}"
fpc="${FPC:-C:/FPC/3.2.2/bin/i386-Win32/fpc.exe}"
build="$here/build"
shared="$build/source/shared"

rm -rf "$build"
mkdir -p "$build/source" "$build/units"
git -C "$source" archive "$REFERENCE_COMMIT" shared | tar -x -C "$build/source"

# Where the server leaves to a player's client what the reference, having no client,
# must do itself: each patch says what and why.
for patch in "$here"/reference/patches/*.patch; do
	patch -s -p1 -d "$build/source" < "$patch"
done

# The units stubs/ stands in for, out of the way so only the stubs are found.
for unit in "$here"/reference/stubs/*.pas; do
	find "$build/source" -iname "$(basename "$unit")" -delete
done

# As the server is built (CMakeLists.txt: Delphi mode, C operators, goto, inline; SERVER),
# for 64-bit Windows, where Single arithmetic is SSE's, as the port's is.
# (Git Bash is told to leave the paths alone: it would make "-FuC:/x" a path of its own.)
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" "$fpc" -Px86_64 -Twin64 -MDelphi -Scgi -O2 -dSERVER -vewn \
	-Fi"$shared" -Fu"$here/reference/stubs" -Fu"$shared" -Fu"$shared/mechanics" \
	-FU"$build/units" -o"$build/reference.dll" "$here/reference/reference.lpr"

echo "built $build/reference.dll from OpenSoldat at $REFERENCE_COMMIT"

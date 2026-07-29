#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
out="${1:-$root/build/x86_64}"
mkdir -p "$out"

winegcc -m64 -I/usr/include/wine/wine/windows \
    -o "$out/XWinTabHelper.dll.so" -shared -O2 \
    "$root/src/XWinTabHelper.c" "$root/src/XWinTabHelper.dll.spec" \
    -lxcb -lxcb-xinput
x86_64-w64-mingw32-gcc -shared -O2 \
    -o "$out/wintab32.dll" \
    "$root/src/WinTab.c" "$root/src/wintab32.def"

sha256sum "$out/wintab32.dll" "$out/XWinTabHelper.dll.so"

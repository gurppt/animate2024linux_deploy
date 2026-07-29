#!/usr/bin/env bash
set -euo pipefail

root="$HOME/softs/animate2024_wine"
ge="$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-1/files"
wineserver="$root/candidates/P11_INPUT_COALESCE_A1/bin/wineserver"
gdiplus="$root/candidates/P11_TIMELINE_FIX_T8/gdiplus.dll"
win32u="$root/candidates/P11_RECTANGLE_W1/win32u.so"
kernelbase="$root/candidates/P11_PROPERTIES_FILECACHE_A1/kernelbase.dll"
dvaui="$root/candidates/P11_PROPERTIES_D1/dvaui.dll"

check_hash() {
    local file="$1" expected="$2" actual
    actual="$(sha256sum "$file" | awk '{print $1}')"
    test "$actual" = "$expected" || {
        echo "Refus : hash inattendu pour $file ($actual)." >&2
        exit 1
    }
}
check_hash "$wineserver" "abc2e20a5253decc49e4910f0991f01aac693061056e671137efde77355d05f5"
check_hash "$gdiplus" "98353f573e3eb475a597bb4a3b01a5f49e35e721bf8fd5ab4040a604fbee72af"
check_hash "$win32u" "5e78b4fda2481cc6cbffbb7ae4f4b8fa32528a384865a0bc3471185da1cd1d5b"
check_hash "$kernelbase" "b87c2fec5558d4ce4d53a2ff2c912aff1ceea99bf5e58c8dd05e7bfd0251de57"
check_hash "$dvaui" "a2ba92552431b9733363936cb4f6b0ac4e08a356f3acfaf184323a3985a9f871"
if pgrep -x wineserver >/dev/null 2>&1; then
    echo "Refus : un wineserver est déjà actif." >&2
    exit 1
fi

export ANIMATE_INPUT_TRACE=0
export ANIMATE_PRESERVE_DRAG_MOVES=1
export ANIMATE_SWP_DEDUP=1
export ANIMATE_FILE_ATTR_CACHE=1
unset ANIMATE_GDIPLUS_NUMERIC_TRACE
export PROTON_USE_XALIA="${PROTON_USE_XALIA:-0}"
export WINEDEBUG="${ANIMATE_WINEDEBUG:--all}"

exec bwrap --dev-bind / / \
    --ro-bind "$wineserver" "$ge/bin/wineserver" \
    --ro-bind "$gdiplus" "$root/prefix/drive_c/windows/system32/gdiplus.dll" \
    --ro-bind "$win32u" "$ge/lib/wine/x86_64-unix/win32u.so" \
    --ro-bind "$kernelbase" "$ge/lib/wine/x86_64-windows/kernelbase.dll" \
    --ro-bind "$dvaui" "$root/prefix/drive_c/Program Files/Adobe/Adobe Animate 2024/dvaui.dll" \
    -- "$root/launch.sh"

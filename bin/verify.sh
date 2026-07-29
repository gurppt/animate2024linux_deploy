#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -d "$script_dir/manifests" ]]; then
    root="$script_dir"
else
    root="$(cd -- "$script_dir/.." && pwd -P)"
fi
cd "$root"
[[ -f manifests/critical.sha256 ]] || {
    echo "manifeste manifests/critical.sha256 absent" >&2
    exit 1
}
sha256sum --check manifests/critical.sha256

for directory in system32 syswow64; do
    for dll in mfc140u.dll msvcp140.dll vcruntime140.dll; do
        [[ -f "app/prefix/drive_c/windows/$directory/$dll" ]] || {
            echo "runtime VC++ manquant: $directory/$dll" >&2
            exit 1
        }
    done
done

xwintab_helper="app/prefix/drive_c/windows/system32/XWinTabHelper.dll.so"
if command -v ldd >/dev/null 2>&1; then
    if ldd "$xwintab_helper" | grep -q 'not found'; then
        echo "dépendance hôte XWinTab manquante (libxcb-xinput.so.0)" >&2
        ldd "$xwintab_helper" >&2
        exit 1
    fi
fi

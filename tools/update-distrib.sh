#!/usr/bin/env bash
set -euo pipefail

deploy_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source_root="${ANIMATE_SOURCE_ROOT:-$HOME/softs/animate2024_wine}"
target="${ANIMATE_DISTRIB_ROOT:-/mnt/shared/animate2024_distrib}"
proton_source="${ANIMATE_PROTON_ROOT:-$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-1}"
umu_source="${ANIMATE_UMU_ROOT:-$HOME/.local/share/umu}"
expected_target="/mnt/shared/animate2024_distrib"

[[ -d "$source_root/prefix" ]] || { echo "Préfixe source absent: $source_root/prefix" >&2; exit 1; }
[[ -d "$proton_source/files" ]] || { echo "GE-Proton source absent: $proton_source" >&2; exit 1; }
[[ -d "$umu_source/steamrt4" ]] || { echo "Runtime UMU source absent: $umu_source/steamrt4" >&2; exit 1; }
[[ "$target" == "$expected_target" || -n "${ANIMATE_ALLOW_CUSTOM_TARGET:-}" ]] ||
    { echo "Cible inattendue: $target" >&2; exit 1; }
if pgrep -f '^C:\\Program Files\\Adobe\\Adobe Animate 2024\\Animate.exe$' >/dev/null; then
    echo "Animate tourne encore. Fermer le préfixe avant le snapshot." >&2
    exit 1
fi

mkdir -p "$target"/{app,bin,docs,logs,manifests,runtime/xdg-data,support}

replace_tree()
{
    local src="$1" dst="$2"
    [[ -d "$src" ]] || { echo "Source absente: $src" >&2; exit 1; }
    if [[ -d "$dst" ]]; then
        find "$dst" -mindepth 1 -delete
    else
        mkdir -p "$dst"
    fi
    cp -a "$src"/. "$dst"/
}

echo "Copie du préfixe Animate..."
replace_tree "$source_root/prefix" "$target/app/prefix"
echo "Copie de GE-Proton11-1..."
replace_tree "$proton_source" "$target/runtime/GE-Proton11-1"
echo "Copie du runtime UMU..."
replace_tree "$umu_source" "$target/runtime/xdg-data/umu"

install -m 0755 "$deploy_root/bin/launch-animate2024.sh" "$target/launch-animate2024.sh"
install -m 0755 "$deploy_root/bin/diagnose.sh" "$target/diagnose.sh"
install -m 0755 "$deploy_root/bin/verify.sh" "$target/verify.sh"
install -m 0755 "$deploy_root/bin/install-host-deps.sh" "$target/install-host-deps.sh"
install -m 0755 "$deploy_root/bin/bwrap-nofonts" "$target/bin/bwrap-nofonts"
install -m 0755 "$source_root/recover_dialog_watcher.sh" "$target/support/recover_dialog_watcher.sh"
mkdir -p "$target/support/p11-properties-a2"
install -m 0755 "$source_root/candidates/P11_INPUT_COALESCE_A1/bin/wineserver" \
    "$target/support/p11-properties-a2/wineserver"
install -m 0644 "$source_root/candidates/P11_TIMELINE_FIX_T8/gdiplus.dll" \
    "$target/support/p11-properties-a2/gdiplus.dll"
install -m 0644 "$source_root/candidates/P11_RECTANGLE_W1/win32u.so" \
    "$target/support/p11-properties-a2/win32u.so"
install -m 0644 "$source_root/candidates/P11_PROPERTIES_FILECACHE_A1/kernelbase.dll" \
    "$target/support/p11-properties-a2/kernelbase.dll"
install -m 0644 "$source_root/candidates/P11_PROPERTIES_D1/dvaui.dll" \
    "$target/support/p11-properties-a2/dvaui.dll"
install -m 0644 "$deploy_root/README.md" "$target/docs/DEPLOYMENT.md"
install -m 0644 "$deploy_root/docs/PATCH_REPRODUCTION.md" \
    "$target/docs/PATCH_REPRODUCTION.md"

cd "$target"
critical=(
    "app/prefix/drive_c/Program Files/Adobe/Adobe Animate 2024/Animate.exe"
    "app/prefix/drive_c/Program Files/Adobe/Adobe Animate 2024/dvaui.dll"
    "app/prefix/drive_c/windows/system32/gdiplus.dll"
    "runtime/GE-Proton11-1/proton"
    "runtime/GE-Proton11-1/files/lib/wine/x86_64-unix/winex11.so"
    "launch-animate2024.sh"
    "bin/bwrap-nofonts"
    "support/recover_dialog_watcher.sh"
    "support/p11-properties-a2/wineserver"
    "support/p11-properties-a2/gdiplus.dll"
    "support/p11-properties-a2/win32u.so"
    "support/p11-properties-a2/kernelbase.dll"
    "support/p11-properties-a2/dvaui.dll"
)
: > manifests/critical.sha256
for file in "${critical[@]}"; do
    [[ -f "$file" ]] || { echo "Fichier critique absent: $file" >&2; exit 1; }
    sha256sum "$file" >> manifests/critical.sha256
done

find app runtime bin support -type f -printf '%P\t%s\n' | sort > manifests/files-and-sizes.tsv
find 'app/prefix/drive_c/Program Files/Adobe' \
     'app/prefix/drive_c/Program Files/Common Files/Adobe' \
     'app/prefix/drive_c/Program Files (x86)/Common Files/Adobe' \
     -type f -print0 | sort -z | xargs -0 sha256sum \
     > manifests/adobe-program-files.sha256
du -sx -B1 . > manifests/disk-usage-bytes.txt
echo "Pack mis à jour dans $target"
./verify.sh

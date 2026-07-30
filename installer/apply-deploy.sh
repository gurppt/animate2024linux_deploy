#!/usr/bin/env bash
set -euo pipefail

installer_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$installer_dir/.." && pwd -P)"

if [[ $# != 2 ]]; then
    echo "Usage: $0 ADOBE_PREFIX FINAL_INSTALL_ROOT" >&2
    exit 64
fi

prefix_source="$(realpath "$1")"
target="$(realpath -m "$2")"
proton_source="${ANIMATE_PROTON_ROOT:-$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-1}"
umu_source="${ANIMATE_UMU_ROOT:-$HOME/.local/share/umu}"
umu_launcher="${ANIMATE_UMU_LAUNCHER:-$(command -v umu-run 2>/dev/null || true)}"
animate_relative='drive_c/Program Files/Adobe/Adobe Animate 2024/Animate.exe'
dvaui_relative='drive_c/Program Files/Adobe/Adobe Animate 2024/dvaui.dll'
gdiplus_real_relative='drive_c/windows/system32/gdiplus_real.dll'
version_proxy_relative='drive_c/Program Files/Adobe/Adobe Animate 2024/version.dll'
version_real_relative='drive_c/Program Files/Adobe/Adobe Animate 2024/version_real.dll'
reference="$repo_root/reference/p11-properties-a2"
xwintab="$repo_root/vendor/xwintab/prebuilt/x86_64"
msxml3="$repo_root/vendor/msxml3"

die()
{
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -f "$prefix_source/$animate_relative" ]] ||
    die "Animate.exe is missing from the phase-1 prefix"
[[ -f "$prefix_source/$dvaui_relative" ]] ||
    die "dvaui.dll is missing from the phase-1 prefix"
[[ -f "$prefix_source/$gdiplus_real_relative" ]] ||
    die "Microsoft GDI+ backend is missing from the phase-1 prefix"
[[ "$(sha256sum "$prefix_source/$gdiplus_real_relative" | awk '{print $1}')" == \
    980ea189929d95eb36e35980fff0c81f7b78de9422771fde8f4ac7a779f5bd89 ]] ||
    die "phase-1 prefix has an unsupported GDI+ backend"
[[ -f "$prefix_source/$version_proxy_relative" &&
   -f "$prefix_source/$version_real_relative" ]] ||
    die "COM/MTA version proxy is missing from the phase-1 prefix"
[[ -x "$proton_source/proton" ]] ||
    die "GE-Proton11-1 is missing: $proton_source"
[[ -d "$umu_source/steamrt4" ]] ||
    die "UMU runtime data is missing: $umu_source"
[[ -x "$umu_launcher" ]] ||
    die "pinned UMU launcher is missing: $umu_launcher"
[[ ! -e "$target" ]] ||
    die "target already exists; refusing to overwrite: $target"

declare -A overlay_hashes=(
    [wineserver]="abc2e20a5253decc49e4910f0991f01aac693061056e671137efde77355d05f5"
    [gdiplus.dll]="98353f573e3eb475a597bb4a3b01a5f49e35e721bf8fd5ab4040a604fbee72af"
    [win32u.so]="5e78b4fda2481cc6cbffbb7ae4f4b8fa32528a384865a0bc3471185da1cd1d5b"
    [kernelbase.dll]="b87c2fec5558d4ce4d53a2ff2c912aff1ceea99bf5e58c8dd05e7bfd0251de57"
)
for file in "${!overlay_hashes[@]}"; do
    [[ -f "$reference/$file" ]] || die "missing deploy reference: $file"
    actual="$(sha256sum "$reference/$file" | awk '{print $1}')"
    [[ "$actual" == "${overlay_hashes[$file]}" ]] ||
        die "unexpected deploy reference hash: $file ($actual)"
done
declare -A xwintab_hashes=(
    [wintab32.dll]="967d39ce85749505e9586b585f6095dad98c86cf00af557d50ea0a0f2fff6e34"
    [XWinTabHelper.dll.so]="f60f1d0b363f1fc5a5075f1ce97efb3f7a1d1017c09998e2712ca6ea4e60eab7"
)
for file in "${!xwintab_hashes[@]}"; do
    [[ "$(sha256sum "$xwintab/$file" | awk '{print $1}')" == \
       "${xwintab_hashes[$file]}" ]] ||
        die "unexpected vendored XWinTab hash: $file"
done
declare -A msxml3_hashes=(
    [system32/msxml3.dll]="dbebbda0c3f26ef348d239c5180d2559129944092095cd1764db0f197b1fbc9d"
    [system32/msxml3r.dll]="dcbf9db53a272510255a7500614933cee21165e1960ee149de2267152034b093"
    [syswow64/msxml3.dll]="a98ce3223f50eeb3fe9f1a28a81393bce13ab3d837dab8f5e66d260a669ce00d"
    [syswow64/msxml3r.dll]="b604ab2b27598de28a5ed89626c41e6ea551eae362e83ec421a52f426b31f551"
)
for file in "${!msxml3_hashes[@]}"; do
    [[ "$(sha256sum "$msxml3/$file" | awk '{print $1}')" == \
       "${msxml3_hashes[$file]}" ]] ||
        die "unexpected vendored MSXML3 hash: $file"
done

winex11="$repo_root/reference/winex11.P10.confirmed.so"
winex11_hash=1fb4c880c8980fdbaad1b320ecc6866ce0ab30695fbe6b9d6e257a44088cadcf
[[ "$(sha256sum "$winex11" | awk '{print $1}')" == "$winex11_hash" ]] ||
    die "unexpected P10 winex11 reference"

mkdir -p "$target"/{app,runtime/xdg-data,runtime/umu-launcher,support/p11-properties-a2,bin,logs,manifests,docs}

echo "Copying phase-1 Adobe prefix..."
cp -a "$prefix_source" "$target/app/prefix"
install -m 0644 "$xwintab/wintab32.dll" \
    "$target/app/prefix/drive_c/windows/system32/wintab32.dll"
install -m 0755 "$xwintab/XWinTabHelper.dll.so" \
    "$target/app/prefix/drive_c/windows/system32/XWinTabHelper.dll.so"
for arch in system32 syswow64; do
    install -m 0644 "$msxml3/$arch/msxml3.dll" \
        "$target/app/prefix/drive_c/windows/$arch/msxml3.dll"
    install -m 0644 "$msxml3/$arch/msxml3r.dll" \
        "$target/app/prefix/drive_c/windows/$arch/msxml3r.dll"
done
echo "Copying pinned GE-Proton11-1..."
cp -a "$proton_source" "$target/runtime/GE-Proton11-1"
echo "Copying UMU runtime data..."
cp -a "$umu_source" "$target/runtime/xdg-data/umu"
install -m 0755 "$umu_launcher" "$target/runtime/umu-launcher/umu-run"

install -m 0644 "$winex11" \
    "$target/runtime/GE-Proton11-1/files/lib/wine/x86_64-unix/winex11.so"
for file in wineserver gdiplus.dll win32u.so kernelbase.dll; do
    install -m 0755 "$reference/$file" "$target/support/p11-properties-a2/$file"
done
"$installer_dir/lib/patch-dvaui.sh" \
    "$target/app/prefix/$dvaui_relative" \
    "$target/support/p11-properties-a2/dvaui.dll"

install -m 0755 "$repo_root/bin/launch-animate2024.sh" "$target/launch-animate2024.sh"
install -m 0755 "$repo_root/bin/verify.sh" "$target/verify.sh"
install -m 0755 "$repo_root/bin/diagnose.sh" "$target/diagnose.sh"
install -m 0755 "$repo_root/bin/install-host-deps.sh" "$target/install-host-deps.sh"
install -m 0755 "$repo_root/bin/bwrap-nofonts" "$target/bin/bwrap-nofonts"
install -m 0755 "$repo_root/bin/recover_dialog_watcher.sh" \
    "$target/support/recover_dialog_watcher.sh"
install -m 0644 "$repo_root/README.md" "$target/docs/DEPLOYMENT.md"
install -m 0644 "$repo_root/docs/PATCH_REPRODUCTION.md" \
    "$target/docs/PATCH_REPRODUCTION.md"

cd "$target"
critical=(
    "app/prefix/$animate_relative"
    "app/prefix/$dvaui_relative"
    "app/prefix/drive_c/windows/system32/wintab32.dll"
    "app/prefix/drive_c/windows/system32/XWinTabHelper.dll.so"
    "app/prefix/drive_c/windows/system32/msxml3.dll"
    "app/prefix/drive_c/windows/system32/msxml3r.dll"
    "app/prefix/drive_c/windows/syswow64/msxml3.dll"
    "app/prefix/drive_c/windows/syswow64/msxml3r.dll"
    "runtime/GE-Proton11-1/proton"
    "runtime/GE-Proton11-1/files/lib/wine/x86_64-unix/winex11.so"
    "runtime/umu-launcher/umu-run"
    "support/p11-properties-a2/wineserver"
    "support/p11-properties-a2/gdiplus.dll"
    "support/p11-properties-a2/win32u.so"
    "support/p11-properties-a2/kernelbase.dll"
    "support/p11-properties-a2/dvaui.dll"
    "launch-animate2024.sh"
    "bin/bwrap-nofonts"
)
: > manifests/critical.sha256
for file in "${critical[@]}"; do
    sha256sum "$file" >> manifests/critical.sha256
done
du -sx -B1 . > manifests/disk-usage-bytes.txt
cat > manifests/install-source.txt <<EOF
phase1_prefix=$prefix_source
proton_source=$proton_source
umu_source=$umu_source
deploy_commit=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo unknown)
built_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

./verify.sh
printf 'Complete relocatable installation created: %s\n' "$target"

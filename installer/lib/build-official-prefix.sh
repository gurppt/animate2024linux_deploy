#!/usr/bin/env bash
set -euo pipefail

[[ $# == 6 ]] || {
    echo "Usage: $0 PROTON_ROOT CC_DIRECTORY CORE_PAYLOAD LANGUAGE_PAYLOAD GDI_BACKEND OUTPUT_PREFIX" >&2
    exit 64
}
proton="$(realpath "$1")"
cc="$(realpath "$2")"
core="$(realpath "$3")"
language="$(realpath "$4")"
gdiplus="$(realpath "$5")"
output="$(realpath -m "$6")"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

[[ -x "$proton/proton" && -f "$cc/packages/ApplicationInfo.xml" &&
   -f "$core/AppFiles/Animate.exe" && -d "$language/AppFiles" &&
   ! -e "$output" ]] || {
    echo "ERROR: invalid builder input or output already exists." >&2
    exit 66
}
[[ "$(sha256sum "$core/AppFiles/Animate.exe" | awk '{print $1}')" == 2f883658cd4691a705af370206ddc7e8a7c12457c0db9102b53e5afde3afe777 ]] ||
    { echo "ERROR: unsupported Animate.exe." >&2; exit 65; }
[[ "$(sha256sum "$gdiplus" | awk '{print $1}')" == 980ea189929d95eb36e35980fff0c81f7b78de9422771fde8f4ac7a779f5bd89 ]] ||
    { echo "ERROR: unsupported GDI+ backend." >&2; exit 65; }
if ! command -v umu-run >/dev/null ||
   ! command -v unzip >/dev/null ||
   ! command -v x86_64-w64-mingw32-gcc >/dev/null; then
    echo "ERROR: umu-run, unzip and mingw-w64 are required." >&2
    exit 69
fi

# The same variable names are intentionally re-established in later isolated
# subshells; no value is expected to escape either group.
# shellcheck disable=SC2030,SC2031
mkdir -p "$output"
(
    export WINEPREFIX="$output"
    export PROTONPATH="$proton"
    export GAMEID=umu-animate-prefix-build
    export STORE=none PROTON_USE_XALIA=0 WINEDEBUG=-all
    umu-run cmd.exe /c exit
)
[[ -f "$output/system.reg" ]] ||
    { echo "ERROR: Proton prefix initialization failed." >&2; exit 70; }

aam="$output/drive_c/Program Files (x86)/Common Files/Adobe/OOBE/PDApp"
adc="$output/drive_c/Program Files/Common Files/Adobe/Adobe Desktop Common"
acc="$output/drive_c/Program Files/Adobe/Adobe Creative Cloud"
mkdir -p "$aam" "$adc" "$acc"
extract_set()
{
    local set="$1" root="$2" package name pimx target
    for package in "$cc/packages/$set"/*; do
        [[ -d "$package" ]] || continue
        name="$(basename "$package")"
        pimx="$package/$name.pimx"
        [[ -f "$pimx" && -f "$package/$name.pima" ]] || continue
        target="$(sed -n 's:.*<target_location>\(.*\)</target_location>.*:\1:p' \
            "$pimx" | head -1)"
        [[ -n "$target" ]] || exit 65
        mkdir -p "$root/$target"
        unzip -q -o "$package/$name.pima" -d "$root/$target"
    done
}
extract_set AAM "$aam"
extract_set ADC "$adc"
extract_set ADC64 "$adc"
extract_set ACC "$acc"
extract_set ACC64 "$acc"

app="$output/drive_c/Program Files/Adobe/Adobe Animate 2024"
startup="$output/drive_c/Program Files/Common Files/Adobe/Startup Scripts CC/Flash"
mkdir -p "$app" "$startup"
cp -a "$core/AppFiles/." "$app/"
[[ ! -d "$core/StartupScriptsCC/Flash" ]] ||
    cp -a "$core/StartupScriptsCC/Flash/." "$startup/"
cp -a "$language/AppFiles/." "$app/"
[[ ! -d "$language/StartupScriptsCC/Flash" ]] ||
    cp -a "$language/StartupScriptsCC/Flash/." "$startup/"

install -m 0644 "$gdiplus" \
    "$output/drive_c/windows/system32/gdiplus_real.dll"
x86_64-w64-mingw32-gcc -shared -O2 -s \
    -o "$app/version.dll" \
    "$repo_root/reference/version_proxy.c" \
    "$repo_root/reference/version_proxy.def" -lole32
version_real="$proton/files/lib/wine/x86_64-windows/version.dll"
[[ "$(sha256sum "$version_real" | awk '{print $1}')" == ec2f7ef63703b1afc3511968b97fc322a401f5c9d6f70d3a3b512feb48078a3c ]] ||
    { echo "ERROR: unsupported Proton version.dll." >&2; exit 65; }
install -m 0644 "$version_real" "$app/version_real.dll"

webview="$output/drive_c/Program Files/Common Files/Adobe/Microsoft/EdgeWebView"
webview_version=140.0.3485.94
webview_source="${ANIMATE_WEBVIEW2_SOURCE:-}"
if [[ ! -f "$webview/msedgewebview2.exe" && -n "$webview_source" ]]; then
    webview_source="$(realpath "$webview_source")"
    [[ -f "$webview_source/msedgewebview2.exe" &&
       -f "$webview_source/WebView2Loader.dll" ]] || {
        echo "ERROR: ANIMATE_WEBVIEW2_SOURCE is not a complete runtime." >&2
        exit 65
    }
    if [[ -f "$webview_source/WEBVIEW2_VERSION" ]]; then
        webview_version="$(<"$webview_source/WEBVIEW2_VERSION")"
    fi
    [[ "$webview_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        echo "ERROR: invalid WebView2 version metadata." >&2
        exit 65
    }
    mkdir -p "$webview"
    cp -a "$webview_source/." "$webview/"
fi
[[ -f "$webview/msedgewebview2.exe" &&
   -f "$webview/WebView2Loader.dll" ]] || {
    echo "ERROR: the official Adobe payload did not provide WebView2." >&2
    exit 65
}
mkdir -p "$webview/Application"
ln -sfn .. "$webview/Application/$webview_version"
printf '%s\n' "$webview_version" >"$output/ANIMATE_WEBVIEW2_VERSION.txt"
(
    export WINEPREFIX="$output"
    export PROTONPATH="$proton"
    export GAMEID=umu-animate-prefix-build
    export STORE=none PROTON_USE_XALIA=0 WINEDEBUG=-all
    edge_key='HKLM\Software\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    state_key='HKLM\Software\WOW6432Node\Microsoft\EdgeUpdate\ClientState\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    umu-run reg.exe add "$edge_key" /v location /t REG_SZ \
        /d 'C:\Program Files\Common Files\Adobe\Microsoft\EdgeWebView\Application' /f
    umu-run reg.exe add "$edge_key" /v name /t REG_SZ \
        /d 'Microsoft Edge WebView2 Runtime' /f
    umu-run reg.exe add "$edge_key" /v pv /t REG_SZ \
        /d "$webview_version" /f
    umu-run reg.exe add "$state_key" /v pv /t REG_SZ \
        /d "$webview_version" /f
)

mkdir -p \
    "$output/drive_c/ProgramData/Adobe/SLStore" \
    "$output/drive_c/users/steamuser/AppData/Local/Adobe" \
    "$output/drive_c/users/steamuser/AppData/Local/Temp" \
    "$output/drive_c/users/steamuser/AppData/LocalLow/Adobe" \
    "$output/drive_c/users/steamuser/AppData/Roaming/Adobe"
if grep -Fq '[Software\\Wine\\Credential Manager\\Generic: Adobe' \
        "$output/user.reg"; then
    echo "ERROR: Adobe account credentials appeared in the public prefix." >&2
    exit 77
fi
cat >"$output/ANIMATE_INSTALLER_PROVENANCE.txt" <<EOF
Construction: public official-CDN identity-clean prefix
Animate.exe sha256: $(sha256sum "$app/Animate.exe" | awk '{print $1}')
GDI+ backend sha256: $(sha256sum "$gdiplus" | awk '{print $1}')
Version proxy sha256: $(sha256sum "$app/version.dll" | awk '{print $1}')
WebView2 runtime: $webview_version (Microsoft Fixed Version, registered locally)
Adobe account/profile state: not imported
Built UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

#!/usr/bin/env bash
set -euo pipefail

[[ $# == 2 ]] || {
    echo "Usage: $0 CACHE_DIRECTORY OUTPUT_DIRECTORY" >&2
    exit 64
}
cache="$(realpath -m "$1")"
output="$(realpath -m "$2")"
version=150.0.4078.105
cab_name="Microsoft.WebView2.FixedVersionRuntime.$version.x64.cab"
cab_url="https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/b401c036-cfb8-4dc4-a58e-8766441df4ac/$cab_name"
cab_sha=26c07cad95615a672cde8c1843a326e18ad25d691f004347544e5e099bff9b92
sdk_version=1.0.3485.44
sdk_name="Microsoft.Web.WebView2.$sdk_version.nupkg"
sdk_url="https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$sdk_version"
sdk_sha=bc09150b179246ac90189649b13be8e6b11b3ac200e817e18df106e1f3cf489e

for command in curl cabextract unzip sha256sum; do
    command -v "$command" >/dev/null ||
        { echo "ERROR: missing required command: $command" >&2; exit 69; }
done
[[ ! -e "$output" ]] || {
    [[ -f "$output/msedgewebview2.exe" &&
       -f "$output/WebView2Loader.dll" &&
       "$(<"$output/WEBVIEW2_VERSION")" == "$version" ]] && exit 0
    echo "ERROR: incomplete WebView2 output already exists: $output" >&2
    exit 73
}

mkdir -p "$cache"
download()
{
    local url="$1" destination="$2" expected="$3" actual
    if [[ -f "$destination" ]]; then
        actual="$(sha256sum "$destination" | awk '{print $1}')"
        [[ "$actual" == "$expected" ]] && return
        rm -f -- "$destination"
    fi
    curl -fL --retry 3 --progress-bar "$url" -o "$destination.partial"
    actual="$(sha256sum "$destination.partial" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || {
        rm -f -- "$destination.partial"
        echo "ERROR: unexpected hash for $(basename "$destination")" >&2
        exit 65
    }
    mv "$destination.partial" "$destination"
}

cab="$cache/$cab_name"
sdk="$cache/$sdk_name"
download "$cab_url" "$cab" "$cab_sha"
download "$sdk_url" "$sdk" "$sdk_sha"

partial="$output.partial"
rm -rf -- "$partial"
mkdir -p "$partial/extracted"
cabextract -q -d "$partial/extracted" "$cab"
runtime="$partial/extracted/Microsoft.WebView2.FixedVersionRuntime.$version.x64"
[[ -f "$runtime/msedgewebview2.exe" && -f "$runtime/msedge.dll" ]] || {
    echo "ERROR: Microsoft Fixed Version runtime extraction is incomplete." >&2
    exit 65
}
cp -a "$runtime/." "$partial/"
unzip -q -j "$sdk" build/native/x64/WebView2Loader.dll -d "$partial"
printf '%s\n' "$version" >"$partial/WEBVIEW2_VERSION"
cat >"$partial/WEBVIEW2_PROVENANCE.txt" <<EOF
Microsoft WebView2 Fixed Version Runtime: $version x64
CAB URL: $cab_url
CAB SHA256: $cab_sha
Microsoft WebView2 SDK loader: $sdk_version x64
NuGet URL: $sdk_url
NuGet SHA256: $sdk_sha
EOF
rm -rf -- "$partial/extracted"
mv "$partial" "$output"
printf 'Verified Microsoft WebView2 runtime ready: %s\n' "$output"

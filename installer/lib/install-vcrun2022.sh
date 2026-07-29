#!/usr/bin/env bash
set -euo pipefail

[[ $# == 3 ]] || {
    echo "Usage: $0 PREFIX PROTON_ROOT CACHE_DIRECTORY" >&2
    exit 64
}
prefix="$(realpath "$1")"
proton="$(realpath "$2")"
cache="$(realpath -m "$3")"
version=14.36.32532
x86_url="https://download.visualstudio.microsoft.com/download/pr/eaab1f82-787d-4fd7-8c73-f782341a0c63/5365A927487945ECB040E143EA770ADBB296074ECE4021B1D14213BDE538C490/VC_redist.x86.exe"
x86_sha=5365a927487945ecb040e143ea770adbb296074ece4021b1d14213bde538c490
x64_url="https://download.visualstudio.microsoft.com/download/pr/eaab1f82-787d-4fd7-8c73-f782341a0c63/917C37D816488545B70AFFD77D6E486E4DD27E2ECE63F6BBAAF486B178B2B888/VC_redist.x64.exe"
x64_sha=917c37d816488545b70affd77d6e486e4dd27e2ece63f6bbaaf486b178b2b888

if ! command -v curl >/dev/null || ! command -v cabextract >/dev/null; then
    echo "ERROR: curl and cabextract are required." >&2
    exit 69
fi
[[ -f "$prefix/system.reg" && -x "$proton/proton" ]] ||
    { echo "ERROR: invalid prefix or Proton root." >&2; exit 66; }
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
    [[ "$actual" == "$expected" ]] ||
        { rm -f -- "$destination.partial"; echo "ERROR: VC++ hash mismatch." >&2; exit 65; }
    mv "$destination.partial" "$destination"
}

download "$x86_url" "$cache/VC_redist.x86.exe" "$x86_sha"
download "$x64_url" "$cache/VC_redist.x64.exe" "$x64_sha"

# Running the Microsoft bootstrapper through Proton can hang indefinitely.
# Its signed payloads are ordinary CABs, so install the exact runtime DLLs
# directly. This is deterministic and does not depend on Wine installer UI.
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work"/{x86-outer,x64-outer,x86-dlls,x64-dlls}
cabextract -q -d "$work/x86-outer" "$cache/VC_redist.x86.exe"
cabextract -q -d "$work/x64-outer" "$cache/VC_redist.x64.exe"
cabextract -q -d "$work/x86-dlls" \
    "$work/x86-outer/a10" "$work/x86-outer/a11"
cabextract -q -d "$work/x64-dlls" \
    "$work/x64-outer/a12" "$work/x64-outer/a13"

install_payload()
{
    local source="$1" suffix="$2" destination="$3" file name
    shopt -s nullglob
    for file in "$source"/*.dll_"$suffix"; do
        name="${file##*/}"
        name="${name%_$suffix}"
        install -m 0644 "$file" "$destination/$name"
    done
    shopt -u nullglob
}
install_payload "$work/x86-dlls" x86 \
    "$prefix/drive_c/windows/syswow64"
install_payload "$work/x64-dlls" amd64 \
    "$prefix/drive_c/windows/system32"

for dll in mfc140.dll mfc140u.dll msvcp140.dll vcruntime140.dll; do
    [[ -f "$prefix/drive_c/windows/system32/$dll" &&
       -f "$prefix/drive_c/windows/syswow64/$dll" ]] || {
        echo "ERROR: VC++ installation did not provide both architectures of $dll." >&2
        exit 70
    }
done
cat >"$prefix/ANIMATE_VCRUN_PROVENANCE.txt" <<EOF
Microsoft Visual C++ 2015-2022 Redistributable: $version
x86 URL: $x86_url
x86 SHA256: $x86_sha
x64 URL: $x64_url
x64 SHA256: $x64_sha
Method: direct extraction of the signed Microsoft CAB payloads
EOF
{
    printf '\nInstalled DLL SHA256:\n'
    for directory in system32 syswow64; do
        for dll in concrt140.dll mfc140.dll mfc140u.dll mfcm140.dll \
            mfcm140u.dll msvcp140.dll msvcp140_1.dll msvcp140_2.dll \
            msvcp140_atomic_wait.dll msvcp140_codecvt_ids.dll \
            vcamp140.dll vccorlib140.dll vcomp140.dll vcruntime140.dll \
            vcruntime140_1.dll; do
            file="$prefix/drive_c/windows/$directory/$dll"
            [[ -f "$file" ]] && sha256sum "$file"
        done
    done
} >>"$prefix/ANIMATE_VCRUN_PROVENANCE.txt"
printf 'Verified Microsoft VC++ 2015-2022 runtime installed.\n'

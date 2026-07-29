#!/usr/bin/env bash
set -euo pipefail

[[ $# == 2 ]] || {
    echo "Usage: $0 CACHE_DIRECTORY OUTPUT_DLL" >&2
    exit 64
}
cache="$(realpath -m "$1")"
output="$(realpath -m "$2")"
mkdir -p "$cache" "$(dirname "$output")"

expected_dll=980ea189929d95eb36e35980fff0c81f7b78de9422771fde8f4ac7a779f5bd89
if [[ -n "${ANIMATE_GDIPLUS_BACKEND:-}" ]]; then
    source="$(realpath "$ANIMATE_GDIPLUS_BACKEND")"
else
    if ! command -v curl >/dev/null ||
       ! command -v cabextract >/dev/null; then
        echo "ERROR: curl and cabextract are required for Microsoft GDI+." >&2
        exit 69
    fi
    sp="$cache/windows6.1-KB976932-X64.exe"
    sp_hash=f4d1d418d91b1619688a482680ee032ffd2b65e420c6d2eaecf8aa3762aa64c8
    url='http://download.windowsupdate.com/msdownload/update/software/svpk/2011/02/windows6.1-kb976932-x64_74865ef2562006e51d7f9333b4a8d45b7a749dab.exe'
    if [[ ! -f "$sp" ||
          "$(sha256sum "$sp" | awk '{print $1}')" != "$sp_hash" ]]; then
        curl --fail --location --retry 4 --continue-at - \
            --output "$sp.part" "$url"
        [[ "$(sha256sum "$sp.part" | awk '{print $1}')" == "$sp_hash" ]] ||
            { echo "ERROR: Windows 7 SP1 hash mismatch." >&2; exit 65; }
        mv "$sp.part" "$sp"
    fi
    temporary="$(mktemp -d)"
    trap 'find "$temporary" -depth -delete 2>/dev/null || true' EXIT
    member='amd64_microsoft.windows.gdiplus_6595b64144ccf1df_1.1.7601.17514_none_2b24536c71ed437a/gdiplus.dll'
    cabextract -q -d "$temporary" -L -F "$member" "$sp"
    source="$temporary/$member"
fi
[[ -f "$source" ]] || { echo "ERROR: GDI+ extraction failed." >&2; exit 65; }
actual="$(sha256sum "$source" | awk '{print $1}')"
[[ "$actual" == "$expected_dll" ]] ||
    { printf 'ERROR: unsupported GDI+ hash: %s\n' "$actual" >&2; exit 65; }
install -m 0644 "$source" "$output"

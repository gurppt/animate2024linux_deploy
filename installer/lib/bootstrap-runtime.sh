#!/usr/bin/env bash
set -euo pipefail

[[ $# == 1 ]] || {
    echo "Usage: $0 RUNTIME_CACHE" >&2
    exit 64
}
cache="$(realpath -m "$1")"
mkdir -p "$cache/downloads"

for command_name in curl tar sha256sum python3; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "ERROR: required bootstrap command is missing: $command_name" >&2
        exit 69
    }
done

download()
{
    local url="$1" expected="$2" output="$3" actual
    if [[ -f "$output" ]]; then
        actual="$(sha256sum "$output" | awk '{print $1}')"
        [[ "$actual" == "$expected" ]] && return 0
    fi
    curl --fail --location --retry 4 --continue-at - \
        --output "$output.part" "$url"
    actual="$(sha256sum "$output.part" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || {
        printf 'ERROR: unexpected SHA-256 for %s: %s\n' "$output" "$actual" >&2
        exit 65
    }
    mv "$output.part" "$output"
}

proton_version=GE-Proton11-1
proton_archive="$cache/downloads/$proton_version.tar.gz"
proton_hash=ce6dd663ea01725a31805ed5c165723a253cdf0945a6642907330742ae2de5e4
proton_url="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$proton_version/$proton_version.tar.gz"
proton_root="$cache/$proton_version"
expected_proton=21e6c15bb0984b88b5c7498bed0d5da868054d1cebf3418306f4012d7f42cb2f

if [[ ! -x "$proton_root/proton" ||
      "$(sha256sum "$proton_root/proton" 2>/dev/null | awk '{print $1}')" != "$expected_proton" ]]; then
    [[ ! -e "$proton_root" ]] || {
        echo "ERROR: incomplete or unsupported runtime exists: $proton_root" >&2
        exit 66
    }
    download "$proton_url" "$proton_hash" "$proton_archive"
    partial="$cache/.proton-extract.$$"
    mkdir "$partial"
    trap 'find "$partial" -depth -delete 2>/dev/null || true' EXIT
    tar -xzf "$proton_archive" -C "$partial"
    [[ -x "$partial/$proton_version/proton" &&
       "$(sha256sum "$partial/$proton_version/proton" | awk '{print $1}')" == "$expected_proton" ]] || {
        echo "ERROR: extracted GE-Proton runtime is unsupported." >&2
        exit 65
    }
    mv "$partial/$proton_version" "$proton_root"
    find "$partial" -depth -delete
    trap - EXIT
fi

umu_version=1.4.0
umu_archive="$cache/downloads/umu-launcher-$umu_version-zipapp.tar"
umu_hash=138ce4b8843608a257d4bee88191ca78a989778bcefd8abb3c1d1aaac3ac6fb8
umu_url="https://github.com/Open-Wine-Components/umu-launcher/releases/download/$umu_version/umu-launcher-$umu_version-zipapp.tar"
umu_root="$cache/umu-launcher-$umu_version"

if [[ ! -x "$umu_root/umu-run" ]]; then
    [[ ! -e "$umu_root" ]] || {
        echo "ERROR: incomplete UMU launcher exists: $umu_root" >&2
        exit 66
    }
    download "$umu_url" "$umu_hash" "$umu_archive"
    partial="$cache/.umu-extract.$$"
    mkdir "$partial"
    trap 'find "$partial" -depth -delete 2>/dev/null || true' EXIT
    tar -xf "$umu_archive" -C "$partial"
    [[ -x "$partial/umu/umu-run" ]] || {
        echo "ERROR: UMU zipapp extraction failed." >&2
        exit 65
    }
    mv "$partial/umu" "$umu_root"
    find "$partial" -depth -delete
    trap - EXIT
fi

version="$("$umu_root/umu-run" --version 2>&1 | head -1)"
[[ "$version" == "umu-launcher version 1.4.0 "* ]] || {
    printf 'ERROR: unsupported UMU launcher: %s\n' "$version" >&2
    exit 65
}

printf 'PROTON_ROOT=%q\n' "$proton_root"
printf 'UMU_LAUNCHER=%q\n' "$umu_root/umu-run"

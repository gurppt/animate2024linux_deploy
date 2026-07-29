#!/usr/bin/env bash
set -euo pipefail

[[ $# == 2 ]] || {
    echo "Usage: $0 DOWNLOAD_CACHE OUTPUT_UMU_DIRECTORY" >&2
    exit 64
}
cache="$(realpath -m "$1")"
umu_root="$(realpath -m "$2")"
runtime="$umu_root/steamrt4"
mkdir -p "$cache" "$umu_root"

version=4.0.20260714.251823
archive_name=SteamLinuxRuntime_4.tar.xz
archive="$cache/$archive_name"
expected=907ffb87b23158e167892f8d5b7ff76852b787d0caf2aad3197561c33624890b
url="https://repo.steampowered.com/steamrt4/images/$version/$archive_name"

for command_name in curl tar sha256sum; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "ERROR: required SteamRT4 command is missing: $command_name" >&2
        exit 69
    }
done

if [[ -x "$runtime/run" &&
      -d "$runtime/steamrt4_platform_$version" &&
      -d "$runtime/pressure-vessel" ]]; then
    exit 0
fi
[[ ! -e "$runtime" ]] || {
    echo "ERROR: incomplete or unsupported SteamRT4 exists: $runtime" >&2
    exit 66
}

if [[ ! -f "$archive" ||
      "$(sha256sum "$archive" | awk '{print $1}')" != "$expected" ]]; then
    curl --fail --location --retry 4 --continue-at - \
        --output "$archive.part" "$url"
    actual="$(sha256sum "$archive.part" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || {
        printf 'ERROR: unexpected SteamRT4 SHA-256: %s\n' "$actual" >&2
        exit 65
    }
    mv "$archive.part" "$archive"
fi

partial="$umu_root/.steamrt4-extract.$$"
mkdir "$partial"
trap 'find "$partial" -depth -delete 2>/dev/null || true' EXIT
tar -xJf "$archive" -C "$partial"
source="$partial/SteamLinuxRuntime_4"
[[ -x "$source/run" &&
   -d "$source/steamrt4_platform_$version" &&
   -d "$source/pressure-vessel" ]] || {
    echo "ERROR: extracted SteamRT4 layout is unsupported." >&2
    exit 65
}
printf 'pinned by animate2024-linux installer\n' >"$source/.installed.ok"
[[ -e "$source/umu" ]] || ln -s _v2-entry-point "$source/umu"
mv "$source" "$runtime"
find "$partial" -depth -delete
trap - EXIT

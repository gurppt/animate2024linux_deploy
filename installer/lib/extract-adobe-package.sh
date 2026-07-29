#!/usr/bin/env bash
set -euo pipefail

[[ $# == 2 ]] ||
    { echo "Usage: $0 ADOBE_PACKAGE.zip OUTPUT_DIRECTORY" >&2; exit 64; }
package="$(realpath "$1")"
output="$(realpath -m "$2")"
workspace="$(mktemp -d)"
trap 'find "$workspace" -depth -delete 2>/dev/null || true' EXIT
[[ -f "$package" && ! -e "$output" ]] || exit 66
mkdir -p "$workspace/extracted" "$workspace/normalized"
7z x -y "-o$workspace/extracted" "$package" >/dev/null
while IFS= read -r -d '' source; do
    relative="${source#"$workspace/extracted"/}"
    relative="${relative//\\//}"
    target="$workspace/normalized/$relative"
    mkdir -p "$(dirname "$target")"
    mv "$source" "$target"
done < <(find "$workspace/extracted" -type f -print0)

# Every FLPR archive has one numeric/package root immediately above AppFiles.
mapfile -t roots < <(find "$workspace/normalized" -type d -name AppFiles \
    -printf '%h\n')
[[ "${#roots[@]}" == 1 ]] || {
    printf 'Expected one Adobe AppFiles root, found %s\n' "${#roots[@]}" >&2
    exit 65
}
"$(dirname "$0")/decode-adobe-payload.sh" "${roots[0]}" "$workspace/decoded"
mv "$workspace/decoded" "$output"

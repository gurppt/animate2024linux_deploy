#!/usr/bin/env bash
set -euo pipefail

decode_one()
{
    local source_root="$1" target_root="$2" source="$3"
    local relative target temporary first
    relative="${source#"$source_root"/}"
    target="$target_root/$relative"
    mkdir -p "$(dirname "$target")"
    first="$(od -An -tx1 -N1 "$source" | tr -d '[:space:]')"
    [[ "$first" == 18 ]] || {
        printf 'Unexpected Adobe payload marker %s: %s\n' "$first" "$relative" >&2
        return 2
    }
    temporary="$target.partial.$$"
    if ! tail -c +2 "$source" |
        xz --format=raw --lzma2=dict=64MiB --decompress --stdout >"$temporary"; then
        find "$temporary" -maxdepth 0 -delete 2>/dev/null || true
        return 3
    fi
    touch -r "$source" "$temporary"
    mv "$temporary" "$target"
}

if [[ "${1:-}" == --one ]]; then
    shift
    decode_one "$@"
    exit
fi
[[ $# -ge 2 && $# -le 3 ]] ||
    { echo "Usage: $0 SOURCE_TREE TARGET_TREE [JOBS]" >&2; exit 64; }
source_root="$(realpath "$1")"
target_root="$(realpath -m "$2")"
jobs="${3:-$(nproc)}"
[[ -d "$source_root" && "$source_root" != "$target_root" ]] || exit 66
mkdir -p "$target_root"
export -f decode_one
find "$source_root" -type f -print0 |
    xargs -0 -r -P "$jobs" -I '{}' \
        bash "$0" --one "$source_root" "$target_root" '{}'
source_count="$(find "$source_root" -type f | wc -l)"
target_count="$(find "$target_root" -type f | wc -l)"
[[ "$source_count" == "$target_count" ]] ||
    { echo "Adobe payload file-count mismatch." >&2; exit 4; }

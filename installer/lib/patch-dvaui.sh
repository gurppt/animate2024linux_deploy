#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 2 ]]; then
    echo "Usage: $0 CLEAN_DVAUI_DLL OUTPUT_DVAUI_DLL" >&2
    exit 64
fi

source_dll="$(realpath "$1")"
output_dll="$(realpath -m "$2")"
[[ -f "$source_dll" ]] || {
    printf 'dvaui.dll not found: %s\n' "$source_dll" >&2
    exit 66
}
[[ "$source_dll" != "$output_dll" ]] || {
    echo "Input and output must differ." >&2
    exit 64
}
mkdir -p "$(dirname "$output_dll")"

python3 - "$source_dll" "$output_dll" <<'PY'
import hashlib
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
data = bytearray(source.read_bytes())

clean_hash = "89654093e3fc0fd2031ab1542573adae1667e3433afd7b66b6447e6e4604b9b8"
p10_hash = "e8db1826f637fba862ab8e695fd02e8a6589691b6aa0a379199003e92de04b50"
final_hash = "a2ba92552431b9733363936cb4f6b0ac4e08a356f3acfaf184323a3985a9f871"

p10 = [
    (0x0c0ad8, bytes.fromhex("48 8b 01"), bytes.fromhex("eb 16 90"), "P10-G"),
    (0x0c89f1, bytes.fromhex("49 8b 07"), bytes.fromhex("eb 3c 90"), "P10-I"),
    (0x147b20, bytes.fromhex("49 8b 07"), bytes.fromhex("eb 70 90"), "P10-J"),
]
p11 = [
    (0x481eff, bytes.fromhex("e8 ac 1a fb ff"), b"\x90" * 5, "P11-D1-a"),
    (0x49432c, bytes.fromhex("e8 7f f6 f9 ff"), b"\x90" * 5, "P11-D1-b"),
]

current = hashlib.sha256(data).hexdigest()
if current == final_hash:
    output.write_bytes(data)
    print(f"dvaui.dll already has the final P11-D1 hash: {output}")
    raise SystemExit(0)

if current == clean_hash:
    patches = p10 + p11
elif current == p10_hash:
    patches = p11
else:
    raise SystemExit(
        "Unsupported dvaui.dll. Expected clean 24.0.13.5, P10, or final P11-D1; "
        f"got sha256={current}"
    )

for offset, expected, replacement, name in patches:
    actual = bytes(data[offset:offset + len(expected)])
    if actual != expected:
        raise SystemExit(
            f"{name}: unexpected bytes at 0x{offset:x}: {actual.hex()}"
        )
    data[offset:offset + len(expected)] = replacement

result = hashlib.sha256(data).hexdigest()
if result != final_hash:
    raise SystemExit(f"Final dvaui.dll verification failed: sha256={result}")

temporary = output.with_name(output.name + ".partial")
temporary.write_bytes(data)
temporary.replace(output)
print(f"Generated verified P11-D1 dvaui.dll: {output}")
PY

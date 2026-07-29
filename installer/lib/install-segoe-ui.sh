#!/usr/bin/env bash
set -euo pipefail

[[ $# == 3 ]] || {
    echo "Usage: $0 PREFIX PROTON_ROOT SEGOE_ZIP" >&2
    exit 64
}
prefix="$(realpath "$1")"
proton="$(realpath "$2")"
archive="$(realpath "$3")"
fonts="$prefix/drive_c/windows/Fonts"

[[ -d "$fonts" && -x "$proton/files/bin/wine" ]] || {
    echo "ERROR: invalid prefix or GE-Proton runtime for Segoe UI." >&2
    exit 66
}
expected_archive=c648c3ab81881ea55f725164e0164fc835e20972a0df87d40bb1898540514aed
actual="$(sha256sum "$archive" | awk '{print $1}')"
[[ "$actual" == "$expected_archive" ]] || {
    printf 'ERROR: unsupported Segoe UI archive SHA-256: %s\n' "$actual" >&2
    exit 65
}

temporary="$(mktemp -d)"
trap 'find "$temporary" -depth -delete 2>/dev/null || true' EXIT
declare -A source_names=(
    [segoeui.ttf]='Segoe UI.ttf'
    [segoeuib.ttf]='Segoe UI Bold.ttf'
    [segoeuii.ttf]='Segoe UI Italic.ttf'
    [segoeuiz.ttf]='Segoe UI BoldItalic.ttf'
    [segoeuil.ttf]='Segoe UI Light.ttf'
    [seguili.ttf]='Segoe UI LightItalic.ttf'
    [seguisb.ttf]='Segoe UI Semibold.ttf'
    [seguisbi.ttf]='Segoe UI Semibold Italic.ttf'
    [segoeuisl.ttf]='Segoe UI Semilight.ttf'
    [seguisli.ttf]='Segoe UI SemiLightItalic.ttf'
    [seguibl.ttf]='Segoe UI Black.ttf'
    [seguibli.ttf]='Segoe UI BlackItalic.ttf'
)
declare -A hashes=(
    [segoeui.ttf]=ba32a222b23d727267cf1aba4e5296fe84ce99b9d910915103fc085d7931bc88
    [segoeuib.ttf]=1b242874a2f57529060e770ba313e027a99d40b3c36e1c7e8b2dece16ad6ed88
    [segoeuii.ttf]=9adf7d619c593ee38c96af06bb15b4bd893e4087bcc1a0b7becee8f4ae15bb1c
    [segoeuiz.ttf]=45e7504e9bbd70ead482ebbddbeec04b2bea9f490b994658a95146cdf0733449
    [segoeuil.ttf]=1a2231bbd4fad4a3ac8c0b8a93af0bce58324a8b3605df16038a9e660a0c072a
    [seguili.ttf]=7726b24daa0c1f47e528d8df78b98717bdb4425bcf37e50330945e32c6d17d7c
    [seguisb.ttf]=9853283466bd43993b9813215281fb9c7090cbd8e9b5453f6d0d040622e117e2
    [seguisbi.ttf]=9959977d9fcf8ebc5fe48f6ee418f05378132b47d21bd5dcc798ad7cff274006
    [segoeuisl.ttf]=38a85c09ee4fc558e7739ebdd1a15a06e2846ebb787cf73b1b6476a3a5b22000
    [seguisli.ttf]=9f84a0a9193fe1d6335967f46606997a208adde053d006b21c03f9375ec5d416
    [seguibl.ttf]=e17738f092c8b02f4443867a7dfcdde66fb4cd6f6b10de8e40b2f3192f8a5835
    [seguibli.ttf]=33212faa85fad61785cd6917172378b798bc9f5d4c47c121437354f47980aa6f
)

for target_name in "${!source_names[@]}"; do
    member="segoe-ui/${source_names[$target_name]}"
    unzip -p "$archive" "$member" >"$temporary/$target_name"
    actual="$(sha256sum "$temporary/$target_name" | awk '{print $1}')"
    [[ "$actual" == "${hashes[$target_name]}" ]] || {
        printf 'ERROR: Segoe UI member hash mismatch: %s\n' "$member" >&2
        exit 65
    }
    install -m 0644 "$temporary/$target_name" "$fonts/$target_name"
done

export WINEPREFIX="$prefix"
export WINEDEBUG=-all
wine="$proton/files/bin/wine"
key='HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
entries=(
    'Segoe UI (TrueType)|segoeui.ttf'
    'Segoe UI Bold (TrueType)|segoeuib.ttf'
    'Segoe UI Italic (TrueType)|segoeuii.ttf'
    'Segoe UI Bold Italic (TrueType)|segoeuiz.ttf'
    'Segoe UI Light (TrueType)|segoeuil.ttf'
    'Segoe UI Light Italic (TrueType)|seguili.ttf'
    'Segoe UI Semibold (TrueType)|seguisb.ttf'
    'Segoe UI Semibold Italic (TrueType)|seguisbi.ttf'
    'Segoe UI Semilight (TrueType)|segoeuisl.ttf'
    'Segoe UI Semilight Italic (TrueType)|seguisli.ttf'
    'Segoe UI Black (TrueType)|seguibl.ttf'
    'Segoe UI Black Italic (TrueType)|seguibli.ttf'
)
for entry in "${entries[@]}"; do
    name="${entry%%|*}"
    value="${entry#*|}"
    "$wine" reg add "$key" /v "$name" /t REG_SZ /d "$value" /f >/dev/null
done
"$wine" reg delete 'HKCU\Software\Wine\Fonts\Replacements' \
    /v 'Segoe UI' /f >/dev/null 2>&1 || true
"$wine" reg delete 'HKCU\Software\Wine\Fonts\Replacements' \
    /v 'Segoe UI Semibold' /f >/dev/null 2>&1 || true
"$proton/files/bin/wineserver" -w
printf 'Installed 12 verified Segoe UI faces into %s\n' "$fonts"

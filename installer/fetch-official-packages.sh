#!/usr/bin/env bash
set -euo pipefail

installer_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
. "$installer_dir/lib/ui.sh"
cache="${ANIMATE_ADOBE_CACHE:-$installer_dir/cache/adobe-official}"
language="${ANIMATE_LANGUAGE:-en_US}"
download_index=0
download_total=3

usage()
{
    cat <<'EOF'
Usage: fetch-official-packages.sh [--language LOCALE|--list-languages]

Default locale: en_US
Examples: en_GB, fr_FR, de_DE, es_ES, ja_JP, zh_CN
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --language)
            [[ $# -ge 2 && -n "$2" ]] || {
                echo "ERROR: --language requires a locale." >&2
                exit 64
            }
            language="$2"
            shift 2
            ;;
        --list-languages)
            printf '%s\n' \
                cs_CZ da_DK de_DE en_AE en_GB en_IL en_US es_ES es_MX \
                fi_FI fr_CA fr_FR fr_MA fr_XM hu_HU it_IT ja_JP ko_KR \
                nb_NO nl_NL pl_PL pt_BR ru_RU sv_SE tr_TR uk_UA zh_CN zh_TW
            exit 0
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 64 ;;
    esac
done

command -v curl >/dev/null || {
    echo "ERROR: curl is required." >&2
    exit 69
}

# Adobe's CDN rejects generic browser/curl requests for these frozen product
# assets. This is the historical Adobe Application Manager identity used by
# Adobe's own downloader; it is not an account token or licence bypass.
user_agent='Adobe Application Manager 10.0'

fetch()
{
    local name="$1" hash="$2" url="$3" target
    download_index=$((download_index + 1))
    target="$cache/$name"
    if [[ -f "$target" ]] &&
       [[ "$(sha256sum "$target" | awk '{print $1}')" == "$hash" ]]; then
        ui_success "[$download_index/$download_total] Already verified: $name"
        return
    fi

    printf '\n%s%s[%s/%s] Downloading %s%s\n' "$UI_BOLD" "$UI_CYAN" \
        "$download_index" "$download_total" "$name" "$UI_RESET"
    curl --fail --location --retry 12 --retry-all-errors \
        --retry-delay 2 --connect-timeout 30 --speed-time 90 --speed-limit 1024 \
        --continue-at - --progress-bar \
        --user-agent "$user_agent" --output "$target.part" "$url"
    actual="$(sha256sum "$target.part" | awk '{print $1}')"
    [[ "$actual" == "$hash" ]] || {
        printf 'ERROR: unexpected SHA-256 for %s: %s\n' "$name" "$actual" >&2
        exit 65
    }
    mv "$target.part" "$target"
    ui_success "SHA-256 verified: $name"
}

# Adobe groups several requested locales into one physical language package.
# English and its fallback locales deliberately use Adobe's 24.0.10.14 pack;
# this exact mixture is declared by the official 24.0.13.5 application
# manifest.
case "$language" in
    en_US|en_GB|en_AE|en_IL|da_DK|fi_FI|hu_HU|nb_NO|uk_UA)
        package=en_US
        hash=f8e41f34083d72e5e532cd22b8ba07b340dc7e38317bc148ce6039e462a35612
        version=24.0.10.14
        asset=326ebe39-c9d9-4c7b-a8cb-3c5637662a64
        ;;
    fr_FR|fr_CA|fr_MA|fr_XM)
        package=fr_FR
        hash=e344de9ff2800cb41b822c34b8f0f106d25daeeeca490dac41084cdd0cbd69de
        ;;
    es_ES|es_MX)
        package=es_ES
        hash=2ff496d1bc78ad1066b97c4ba9040ce38035b495d9b9c81ae8ccb95f352d389e
        ;;
    cs_CZ) package=cs_CZ; hash=e070f19c36fec9d5737a6ba6318e94abaab5b3bce3e16fe3b5ce2c75837f35d1 ;;
    de_DE) package=de_DE; hash=59a611a6b271f56ce16fb19c12396957479ede29b522261e4735167a9f074c40 ;;
    it_IT) package=it_IT; hash=b7ceaaa4b4ec6428367569748b854284437c92a5530dd8fb983728335c8c9f96 ;;
    ja_JP) package=ja_JP; hash=fe6cd0861a576dc8967c7ccb4307148b24711f27e9f464cb1ec9e1bbad33c4f3 ;;
    ko_KR) package=ko_KR; hash=c7219723ce09540d297eada8ca95518464a62391eba1e46da06e15a212b3dbdc ;;
    nl_NL) package=nl_NL; hash=6c13cd3e2c81fffaa9407292761ee2cf1a307c9904ae935a74875c9f17c15718 ;;
    pl_PL) package=pl_PL; hash=04902b2557f15ba826b48f2ce09f1cf3de24a1821860e31d6906814143b198d8 ;;
    pt_BR) package=pt_BR; hash=46af7ec81f781bfa5278fe010dfd95726d29fb7a9c38debce97b1588461dc440 ;;
    ru_RU) package=ru_RU; hash=6c1ba3c0942f41979614ac47ae1deef4dfdd8b8b55f0d9dcdd3a64a12410995a ;;
    sv_SE) package=sv_SE; hash=4ad337113a2d0e5d989fa1ee9893d18a56f295247b7548bddfe44d52368ad22d ;;
    tr_TR) package=tr_TR; hash=1fd623323f141d72b158267026653e196fb10c2784f2e8ad99cfed7e006a9edc ;;
    zh_CN) package=zh_CN; hash=923f890ebef167a43845e989bb9ce0b4d3c9c404745fb84a31a17d354e4f98d2 ;;
    zh_TW) package=zh_TW; hash=5f122c335f6fe5d2d7d3dff4ce7012aa5abfc45fa0c9b5ba7a3b9530e40a66ae ;;
    *) printf 'ERROR: unsupported locale: %s\n' "$language" >&2; exit 64 ;;
esac
version="${version:-24.0.13.5}"
asset="${asset:-8128cf76-9cf5-4e5c-8b82-0b11ae25fa24}"
mkdir -p "$cache"

fetch \
    ACCCx6_10_0_252_3.zip \
    6472f7f2c1e5f205f8ef5439e51fad61008d9434df4d0d32afede51ff71fa655 \
    'https://ccmdls.adobe.com/AdobeProducts/StandaloneBuilds/ACCC/ESD/6.10.0/252.3/win64/ACCCx6_10_0_252_3.zip'

fetch \
    AdobeAnimate24.0-mul.zip \
    400761011cf1183b5eb8d42e428bd90a1660d45e5473ec08d3506d0b4145a3d0 \
    'https://ccmdls.adobe.com/AdobeProducts/FLPR/24.0.13.5/win64/8128cf76-9cf5-4e5c-8b82-0b11ae25fa24/AdobeAnimate24.0-mul.zip'

fetch \
    "AdobeAnimate24.0-$package.zip" \
    "$hash" \
    "https://ccmdls.adobe.com/AdobeProducts/FLPR/$version/win64/$asset/AdobeAnimate24.0-$package.zip"

cat >"$cache/selection.env" <<EOF
ANIMATE_REQUESTED_LOCALE='$language'
ANIMATE_LANGUAGE_PACKAGE='$package'
ANIMATE_LANGUAGE_ARCHIVE='AdobeAnimate24.0-$package.zip'
EOF
printf '\nOfficial package cache ready: %s\n' "$cache"
printf 'Requested locale: %s (Adobe package: %s)\n' "$language" "$package"

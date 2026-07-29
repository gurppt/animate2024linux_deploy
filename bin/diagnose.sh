#!/usr/bin/env bash
set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -d "$script_dir/app" && -d "$script_dir/runtime" ]]; then
    root="$script_dir"
else
    root="$(cd -- "$script_dir/.." && pwd -P)"
fi
printf 'Pack: %s\n' "$root"
printf 'OS: '
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    printf '%s %s\n' "${PRETTY_NAME:-$ID}" "${VERSION_ID:-}"
else
    uname -sr
fi
printf 'Session: %s / DISPLAY=%s\n' "${XDG_SESSION_TYPE:-inconnue}" "${DISPLAY:-absent}"
printf 'Date UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
timedatectl show -p NTPSynchronized -p Timezone 2>/dev/null || true
if [[ -x "$root/runtime/umu-launcher/umu-run" ]]; then
    printf 'umu-run: %s (bundled)\n' "$root/runtime/umu-launcher/umu-run"
else
    printf 'umu-run: %s\n' "$(command -v umu-run 2>/dev/null || echo absent)"
fi
printf 'xinput: %s\n' "$(command -v xinput 2>/dev/null || echo absent)"
printf 'wmctrl: %s\n' "$(command -v wmctrl 2>/dev/null || echo absent)"
printf 'xdotool: %s\n' "$(command -v xdotool 2>/dev/null || echo absent)"
printf '\nGPU PCI:\n'
lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' || true
printf '\nOpenGL:\n'
glxinfo -B 2>/dev/null | grep -E 'direct rendering|OpenGL vendor|OpenGL renderer|OpenGL version' || true
printf '\nVulkan:\n'
vulkaninfo --summary 2>/dev/null | sed -n '1,100p' || true
printf '\nEspace pack:\n'
du -sh "$root" 2>/dev/null || true

printf '\nAdobe network endpoints (host TLS):\n'
if command -v curl >/dev/null 2>&1; then
    for endpoint in \
        https://oobe.adobe.com \
        https://ims-prod06.adobelogin.com \
        https://lcs-cops.adobe.io \
        https://resources.licenses.adobe.com \
        https://delegated.adobelogin.com; do
        status="$(curl -sS -o /dev/null -I --max-time 10 \
            -w '%{http_code}' "$endpoint" 2>&1)" || true
        printf '%-45s %s\n' "$endpoint" "${status:-failed}"
    done
else
    printf 'curl absent\n'
fi

prefix="$root/app/prefix"
if [[ -f "$prefix/user.reg" ]]; then
    printf '\nAdobe prefix identity state:\n'
    printf 'Credential Manager Adobe sections: '
    grep -cF '[Software\\Wine\\Credential Manager\\Generic: Adobe' \
        "$prefix/user.reg" || true
    printf 'WebView2 version: '
    if [[ -f "$prefix/ANIMATE_WEBVIEW2_VERSION.txt" ]]; then
        cat "$prefix/ANIMATE_WEBVIEW2_VERSION.txt"
    else
        printf 'unknown\n'
    fi
fi

printf '\nRecent NGL workflow diagnostics:\n'
ngl_root="$prefix/drive_c/users/steamuser/AppData/Local/Temp/NGL"
if [[ -d "$ngl_root" ]]; then
    while IFS= read -r file; do
        printf '%s\n' "--- $file"
        grep -aEi 'error|failed|workflow|sign-in|CefBrowser|network|internet|10000' \
            "$file" 2>/dev/null | tail -80 || true
    done < <(find "$ngl_root" -maxdepth 1 -type f -name '*.log' | sort)
else
    printf 'No NGL log directory yet.\n'
fi

printf '\nPersistent launch logs:\n'
find "$root/logs" -maxdepth 1 -type f -name 'launch-*.log' \
    -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort | tail -10 || true

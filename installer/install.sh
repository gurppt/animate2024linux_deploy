#!/usr/bin/env bash
set -euo pipefail

installer_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
. "$installer_dir/lib/ui.sh"
install_root="${ANIMATE_INSTALL_ROOT:-$HOME/.local/share/animate2024-linux}"
work_root="${ANIMATE_INSTALL_WORK:-$installer_dir/work}"
state_root="$work_root/state"
config_root="${XDG_CONFIG_HOME:-$HOME/.config}/animate2024-linux"
install_record="$config_root/installation.conf"
records_root="$config_root/installations.d"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}/animate2024-linux"
yes=0
action=all
language="${ANIMATE_LANGUAGE:-en_US}"
install_root_explicit=0
keep_build_cache=0

usage()
{
    cat <<EOF
    Animate 2024 Linux guided installer

Usage: $0 [--check|--phase1|--phase2|--all] [OPTIONS]

  --check    detect the system and Adobe source; change nothing
  --phase1   create or validate the clean Adobe prefix
  --phase2   deploy a prefix previously validated by phase 1
  --all      phase 1 then compatibility deploy (default)
  --yes      accept the host-package installation prompt
  --language select the Animate UI locale (default: $language)
  --install-dir PATH
             final installation directory
  --keep-build-cache
             retain downloaded and intermediate build files after success
  --uninstall
             safely remove the registered Animate installation

Environment:
  ANIMATE_INSTALL_ROOT       final destination (default: $install_root)
  ANIMATE_INSTALL_WORK       resumable work directory
  ANIMATE_EXISTING_PREFIX    use an existing legitimate prefix
  ANIMATE_SOURCE_MODE        auto (default), official, or private-template
  ANIMATE_PROTON_ROOT        optional pre-existing GE-Proton11-1 directory
  ANIMATE_LANGUAGE           UI locale, for example en_US or fr_FR
  ANIMATE_GDIPLUS_BACKEND    optional verified local Win7 SP1 x64 GDI+ DLL
  ANIMATE_WEBVIEW2_SOURCE    optional pre-extracted Microsoft WebView2 directory
  ANIMATE_SEGOE_SOURCE       optional verified Segoe-UI-Font-Family.zip
EOF
}

die()
{
    printf '\n'
    ui_error "$*"
    exit 1
}

say()
{
    printf '\n%s%s▶%s %s%s%s\n' "$UI_BLUE" "$UI_BOLD" "$UI_RESET" \
        "$UI_BOLD" "$*" "$UI_RESET"
}

confirm()
{
    local answer
    (( yes )) && return 0
    printf '%s [y/N] ' "$1"
    read -r answer
    [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]]
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) action=check ;;
        --phase1) action=phase1 ;;
        --phase2) action=phase2 ;;
        --all) action=all ;;
        --uninstall) action=uninstall ;;
        --yes) yes=1 ;;
        --keep-build-cache) keep_build_cache=1 ;;
        --install-dir)
            [[ $# -ge 2 && -n "$2" ]] ||
                die "--install-dir requires a path"
            install_root="$2"
            install_root_explicit=1
            shift
            ;;
        --language)
            [[ $# -ge 2 && -n "$2" ]] ||
                die "--language requires a locale"
            language="$2"
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
    shift
done

ui_banner

work_root="${work_root/#\~/$HOME}"
work_root="$(realpath -m "$work_root")"
[[ "$work_root" == /* &&
   "$work_root" != / &&
   "$work_root" != "$HOME" &&
   "$work_root" != "$installer_dir" ]] ||
    die "unsafe build workspace: $work_root"
state_root="$work_root/state"

mkdir -p "$state_home/logs"
session_log="$state_home/logs/install-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"
exec > >(tee -a "$session_log") 2>&1
ui_key "Session log" "$session_log"

read_install_record()
{
    local record="${1:-$install_record}"
    [[ -f "$record" ]] || return 1
    INSTALL_ID="$(sed -n 's/^install_id=//p' "$record" | head -1)"
    INSTALLED_AT_UTC="$(sed -n 's/^installed_at_utc=//p' "$record" | head -1)"
    INSTALL_ROOT="$(sed -n 's/^install_root=//p' "$record" | head -1)"
    INSTALL_RECORD="$record"
    [[ -n "${INSTALL_ID:-}" && -n "${INSTALL_ROOT:-}" ]] || return 1
}

safe_registered_install()
{
    local candidate="${1:-}"
    [[ -n "$candidate" && "$candidate" == /* ]] || return 1
    [[ "$candidate" != / && "$candidate" != "$HOME" ]] || return 1
    [[ -f "$candidate/manifests/install-source.txt" ]] || return 1
    [[ -f "$candidate/manifests/critical.sha256" ]] || return 1
    [[ -f "$candidate/app/prefix/drive_c/Program Files/Adobe/Adobe Animate 2024/Animate.exe" ]]
}

find_registered_install()
{
    local record manifest candidate
    if read_install_record && safe_registered_install "$INSTALL_ROOT"; then
        return 0
    fi
    if [[ -d "$records_root" ]]; then
        while IFS= read -r -d '' record; do
            if read_install_record "$record" &&
               safe_registered_install "$INSTALL_ROOT"; then
                return 0
            fi
        done < <(find "$records_root" -maxdepth 1 -type f -name '*.conf' -print0)
    fi
    # Recovery path if ~/.config was removed or another clone runs uninstall.
    for candidate in "$HOME/.local/share" "$HOME/softs"; do
        [[ -d "$candidate" ]] || continue
        while IFS= read -r -d '' manifest; do
            INSTALL_ROOT="${manifest%/manifests/managed-install.conf}"
            if safe_registered_install "$INSTALL_ROOT"; then
                INSTALL_ID="$(sed -n 's/^install_id=//p' "$manifest" | head -1)"
                INSTALLED_AT_UTC="$(sed -n 's/^installed_at_utc=//p' "$manifest" | head -1)"
                INSTALL_RECORD="$manifest"
                return 0
            fi
        done < <(find "$candidate" -maxdepth 5 -type f \
            -path '*/manifests/managed-install.conf' -print0 2>/dev/null)
    done
    return 1
}

stop_install_processes()
{
    local candidate cmdline envline pid child deadline
    local -a pending=() targets=()
    declare -A selected=()

    # Do not remove a live prefix. Select processes whose command line or
    # environment refers to this exact managed installation, then include
    # their descendants (Wine children can expose only Windows paths).
    for candidate in /proc/[0-9]*; do
        pid="${candidate##*/}"
        [[ "$pid" != "$$" ]] || continue
        cmdline=
        envline=
        [[ ! -r "$candidate/cmdline" ]] ||
            cmdline="$(tr '\0' ' ' 2>/dev/null <"$candidate/cmdline" || true)"
        [[ ! -r "$candidate/environ" ]] ||
            envline="$(tr '\0' '\n' 2>/dev/null <"$candidate/environ" || true)"
        if [[ "$cmdline" == *"$INSTALL_ROOT/"* ||
              "$envline" == *"=$INSTALL_ROOT/"* ]]; then
            selected["$pid"]=1
            pending+=("$pid")
        fi
    done
    while ((${#pending[@]})); do
        pid="${pending[0]}"
        pending=("${pending[@]:1}")
        while IFS= read -r child; do
            [[ -n "$child" && -z "${selected[$child]:-}" ]] || continue
            selected["$child"]=1
            pending+=("$child")
        done < <(pgrep -P "$pid" 2>/dev/null || true)
    done
    ((${#selected[@]})) || return 0
    mapfile -t targets < <(printf '%s\n' "${!selected[@]}" | sort -rn)
    ui_warn "Stopping ${#targets[@]} running process(es) from this installation."
    kill -TERM "${targets[@]}" 2>/dev/null || true
    deadline=$((SECONDS + 10))
    while ((SECONDS < deadline)); do
        pending=()
        for pid in "${targets[@]}"; do
            kill -0 "$pid" 2>/dev/null && pending+=("$pid")
        done
        ((${#pending[@]})) || return 0
        sleep 1
    done
    kill -KILL "${pending[@]}" 2>/dev/null || true
}

uninstall_registered()
{
    if (( install_root_explicit )); then
        INSTALL_ROOT="${install_root/#\~/$HOME}"
        INSTALL_ROOT="$(realpath -m "$INSTALL_ROOT")"
        INSTALL_ID=explicit-path
        INSTALLED_AT_UTC=unknown
        INSTALL_RECORD=
        safe_registered_install "$INSTALL_ROOT" ||
            die "no managed Animate installation was found at $INSTALL_ROOT"
    else
        find_registered_install ||
            die "no managed Animate installation was found. Use --install-dir PATH --uninstall if its registry was removed"
    fi
    safe_registered_install "$INSTALL_ROOT" ||
        die "the registered path does not look like a managed Animate installation: $INSTALL_ROOT"
    ui_key "Installation" "$INSTALL_ROOT"
    ui_key "Installed" "${INSTALLED_AT_UTC:-unknown}"
    ui_key "ID" "$INSTALL_ID"
    confirm "Remove this complete installation?" || {
        ui_warn "Uninstall cancelled."
        exit 0
    }
    stop_install_processes
    rm -rf -- "$INSTALL_ROOT"
    [[ -z "${INSTALL_RECORD:-}" ]] || rm -f -- "$INSTALL_RECORD"
    if [[ -d "$records_root" ]]; then
        while IFS= read -r -d '' record; do
            recorded_root="$(sed -n 's/^install_root=//p' "$record" | head -1)"
            [[ "$recorded_root" != "$INSTALL_ROOT" ]] || rm -f -- "$record"
        done < <(find "$records_root" -maxdepth 1 -type f -name '*.conf' -print0)
    fi
    if [[ -f "$install_record" ]]; then
        recorded_root="$(sed -n 's/^install_root=//p' "$install_record" | head -1)"
        [[ "$recorded_root" != "$INSTALL_ROOT" ]] || rm -f -- "$install_record"
    fi
    rmdir "$records_root" "$config_root" 2>/dev/null || true
    ui_success "Animate installation removed."
    exit 0
}

if [[ "$action" == uninstall ]]; then
    uninstall_registered
fi

if (( ! install_root_explicit )) &&
   read_install_record && safe_registered_install "$INSTALL_ROOT"; then
    ui_warn "A managed Animate installation is already registered."
    ui_key "Installation" "$INSTALL_ROOT"
    ui_key "Installed" "${INSTALLED_AT_UTC:-unknown}"
    ui_key "ID" "$INSTALL_ID"
    if (( yes )); then
        ui_success "The existing installation is kept; nothing to do."
        exit 0
    fi
    printf '\nChoose: %s[Enter]%s keep/exit, %su%s uninstall: ' \
        "$UI_BOLD" "$UI_RESET" "$UI_BOLD" "$UI_RESET"
    read -r existing_action
    if [[ "$existing_action" == [uU] ]]; then
        uninstall_registered
    fi
    ui_success "Existing installation kept."
    exit 0
fi

if (( ! install_root_explicit && ! yes )) && [[ -t 0 ]]; then
    while true; do
        printf '\nWhere should the complete application be installed?\n'
        printf 'Press Enter for the default. Enter an absolute path or a path beginning with ~/.\n'
        printf 'Installation folder [%s]: ' "$install_root"
        read -r selected_root
        if [[ -z "$selected_root" ]]; then
            break
        fi
        case "$selected_root" in
            y|Y|yes|YES|n|N|no|NO)
                ui_warn "'$selected_root' is not treated as a folder name."
                continue
                ;;
            /*|~/*)
                install_root="$selected_root"
                break
                ;;
            *)
                ui_warn "Use an absolute path, for example $HOME/softs/animate."
                ;;
        esac
    done
fi
install_root="${install_root/#\\~/$HOME}"
install_root="$(realpath -m "$install_root")"
[[ "$install_root" != *$'\n'* ]] ||
    die "the installation directory cannot contain a newline"
[[ "$install_root" == /* && "$install_root" != / && "$install_root" != "$HOME" ]] ||
    die "unsafe installation directory: $install_root"
if [[ "$install_root" == "$work_root" ||
      "$install_root" == "$work_root/"* ||
      "$work_root" == "$install_root/"* ]]; then
    die "the installation directory and build workspace must not overlap"
fi

if [[ -e "$install_root" ]]; then
    if [[ -d "$install_root" ]] &&
       [[ -z "$(find "$install_root" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        ui_info "The selected destination exists and is empty; it will be used."
    elif [[ -x "$install_root/verify.sh" ]] &&
         "$install_root/verify.sh" >/dev/null 2>&1; then
        die "a verified Animate installation already exists at $install_root; uninstall it first"
    else
        die "the selected destination already exists and is not empty: $install_root"
    fi
fi

if [[ "$action" == phase2 && -f "$state_root/source.env" ]]; then
    # Generated locally by this installer from fixed-format validated values.
    # shellcheck disable=SC1090,SC1091
    . "$state_root/source.env"
    language="${REQUESTED_LOCALE:-$language}"
fi

[[ -r /etc/os-release ]] || die "/etc/os-release is missing"
. /etc/os-release
os_id="${ID:-unknown}"
os_like="${ID_LIKE:-}"
debian_family=0
case " $os_id $os_like " in
    *" debian "*|*" ubuntu "*) debian_family=1 ;;
esac
session="${XDG_SESSION_TYPE:-unknown}"
arch="$(uname -m)"
[[ "$arch" == x86_64 ]] || die "x86-64 is required (detected: $arch)"

existing_parent()
{
    local probe="$1" parent
    while [[ ! -e "$probe" ]]; do
        parent="$(dirname "$probe")"
        [[ "$parent" != "$probe" ]] || break
        probe="$parent"
    done
    printf '%s\n' "$probe"
}

space_probe="$(existing_parent "$install_root")"
work_space_probe="$(existing_parent "$work_root")"
available_kib="$(df -Pk "$space_probe" | awk 'NR==2 {print $4}')"
work_available_kib="$(df -Pk "$work_space_probe" | awk 'NR==2 {print $4}')"
install_device="$(df -P "$space_probe" | awk 'NR==2 {print $1}')"
work_device="$(df -P "$work_space_probe" | awk 'NR==2 {print $1}')"
if [[ "$install_device" == "$work_device" ]]; then
    required_kib=$((20 * 1024 * 1024))
    work_required_kib=0
else
    required_kib=$((12 * 1024 * 1024))
    work_required_kib=$((15 * 1024 * 1024))
fi
renderer="$(glxinfo -B 2>/dev/null |
    sed -n 's/^OpenGL renderer string: //p' | head -1 || true)"
gpu_pci="$(lspci 2>/dev/null |
    grep -Ei 'VGA compatible controller|3D controller' || true)"

source_mode=
source_path=
existing="${ANIMATE_EXISTING_PREFIX:-}"
requested_source_mode="${ANIMATE_SOURCE_MODE:-auto}"
official_cache="$installer_dir/cache/adobe-official"
core="$official_cache/AdobeAnimate24.0-mul.zip"
cc_archive="$official_cache/ACCCx6_10_0_252_3.zip"
private_template="$installer_dir/cache/prefix-template"
case "$requested_source_mode" in
    auto|official|private-template) ;;
    *) die "ANIMATE_SOURCE_MODE must be auto, official, or private-template" ;;
esac
if [[ -n "$existing" ]]; then
    source_mode=prefix
    source_path="$(realpath "$existing")"
elif [[ "$requested_source_mode" == private-template ]]; then
    [[ -f "$private_template/drive_c/Program Files/Adobe/Adobe Animate 2024/Animate.exe" ]] ||
        die "the requested private template is unavailable"
    source_mode=private-template
    source_path="$private_template"
elif [[ "$requested_source_mode" == auto &&
        -f "$private_template/drive_c/Program Files/Adobe/Adobe Animate 2024/Animate.exe" ]]; then
    source_mode=private-template
    source_path="$private_template"
elif [[ -f "$core" && -f "$cc_archive" ]]; then
    source_mode=official-cache
    source_path="$official_cache"
else
    source_mode=official-download
    source_path="$official_cache"
fi
if [[ "$action" == phase2 && -f "$state_root/adobe-prefix.path" ]]; then
    source_mode=phase1-state
    source_path="$(<"$state_root/adobe-prefix.path")"
fi

ui_step 1 6 "System preflight"
printf 'Distribution : %s (%s)\n' "${PRETTY_NAME:-$os_id}" "$os_id"
printf 'Architecture : %s\n' "$arch"
printf 'Session      : %s\n' "$session"
printf 'OpenGL GPU   : %s\n' "${renderer:-not detected}"
[[ -z "$gpu_pci" ]] || printf '%s\n' "$gpu_pci"
printf 'Free space   : %s GiB\n' "$((available_kib / 1024 / 1024))"
printf 'Destination  : %s\n' "$install_root"
printf 'Work area    : %s\n' "$work_root"
if [[ "$install_device" != "$work_device" ]]; then
    printf 'Work free    : %s GiB (separate filesystem)\n' \
        "$((work_available_kib / 1024 / 1024))"
fi
printf 'Adobe source : %s%s\n' "$source_mode" \
    "${source_path:+ ($source_path)}"
printf 'UI locale    : %s\n' "$language"
printf 'Session log  : %s\n' "$session_log"

case "$os_id" in
    debian|ubuntu|pop|linuxmint)
        printf '\nHost dependencies are managed automatically when approved.\n'
        printf 'APT indexes are refreshed and i386 multiarch is enabled; no full system upgrade is performed.\n'
        ;;
    fedora)
        printf '\nInstall Python, curl, tar, p7zip, xz, unzip, cabextract, mingw-w64, bubblewrap, xdotool, wmctrl, xinput, Vulkan and matching 32-bit GPU drivers.\n'
        ;;
    arch|manjaro)
        printf '\nInstall Python, curl, tar, p7zip, xz, unzip, cabextract, mingw-w64, bubblewrap, xdotool, wmctrl, xorg-xinput, mesa-utils, vulkan-tools and lib32-vulkan-icd-loader.\n'
        ;;
    *)
        printf '\nThis distribution is not yet automated; use the dependency list in the README.\n'
        ;;
esac

[[ "$session" != wayland ]] ||
    printf '\nWARNING: the compatibility patches currently target an X11 session.\n'
(( available_kib >= required_kib )) ||
    die "insufficient destination space; $((required_kib / 1024 / 1024)) GiB is required"
(( work_required_kib == 0 || work_available_kib >= work_required_kib )) ||
    die "insufficient workspace space; $((work_required_kib / 1024 / 1024)) GiB is required"
if [[ "$action" != phase2 && "$source_mode" == official-download ]]; then
    printf '\nThe exact frozen Adobe packages will be downloaded from Adobe and hash-verified.\n'
fi

if [[ "$action" == check ]]; then
    say "Preflight complete; no files were changed"
    exit 0
fi

if (( ! yes )); then
    confirm "Proceed with this destination: $install_root ?" ||
        die "installation cancelled before downloads"
fi

missing=()
for required in python3 curl tar 7z xz unzip cabextract \
                x86_64-w64-mingw32-gcc bwrap; do
    command -v "$required" >/dev/null 2>&1 || missing+=("$required")
done
host_setup_reasons=()
if (( ${#missing[@]} )); then
    host_setup_reasons+=("missing commands: ${missing[*]}")
fi
if (( debian_family )); then
    if ! dpkg --print-foreign-architectures 2>/dev/null | grep -qx i386; then
        host_setup_reasons+=("Debian i386 multiarch is not enabled")
    else
        for package in libgl1-mesa-dri:i386 libvulkan1:i386; do
            if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
                 grep -qx 'install ok installed'; then
                host_setup_reasons+=("missing package: $package")
            fi
        done
    fi
    if ! dpkg-query -W -f='${Status}' libxcb-xinput0 2>/dev/null |
         grep -qx 'install ok installed'; then
        host_setup_reasons+=("missing package: libxcb-xinput0")
    fi
fi
if (( ${#host_setup_reasons[@]} )); then
    printf '\n'
    for reason in "${host_setup_reasons[@]}"; do
        ui_warn "$reason"
    done
    confirm "Install the required host packages now?" ||
        die "host dependencies are incomplete"
    command -v sudo >/dev/null 2>&1 ||
        die "sudo is required to install host packages"
    case "$os_id" in
        debian|ubuntu|pop|linuxmint)
            if command -v dpkg >/dev/null 2>&1 &&
               ! dpkg --print-foreign-architectures | grep -qx i386; then
                ui_info "Enabling Debian i386 multiarch for Proton graphics libraries"
                sudo dpkg --add-architecture i386
            fi
            ui_info "Refreshing APT package indexes (no full-upgrade)"
            sudo apt-get update
            sudo apt-get install -y python3 curl tar p7zip-full xz-utils unzip \
                cabextract gcc-mingw-w64-x86-64-win32 bubblewrap \
                xdotool wmctrl xinput \
                mesa-utils vulkan-tools libxcb-xinput0 \
                libgl1-mesa-dri:i386 libvulkan1:i386
            ;;
        fedora)
            sudo dnf install -y python3 curl tar p7zip p7zip-plugins xz unzip \
                cabextract mingw64-gcc bubblewrap xdotool wmctrl xinput \
                glx-utils vulkan-tools
            ;;
        arch|manjaro)
            sudo pacman -S --needed python curl tar p7zip xz unzip cabextract \
                mingw-w64-gcc bubblewrap xdotool wmctrl xorg-xinput \
                mesa-utils vulkan-tools lib32-vulkan-icd-loader
            ;;
        *)
            die "automatic host dependency installation is unsupported on $os_id"
            ;;
    esac
fi
for required in python3 curl tar 7z xz unzip cabextract \
                x86_64-w64-mingw32-gcc bwrap; do
    command -v "$required" >/dev/null 2>&1 ||
        die "required command is still missing after host setup: $required"
done

mkdir -p "$state_root" "$work_root/logs"
if [[ "$action" != phase2 ]]; then
    {
        printf 'SOURCE_MODE=%q\n' "$source_mode"
        printf 'SOURCE_PATH=%q\n' "$source_path"
        printf 'REQUESTED_LOCALE=%q\n' "$language"
    } >"$state_root/source.env"
fi

animate_relative='drive_c/Program Files/Adobe/Adobe Animate 2024/Animate.exe'
adobe_prefix="$work_root/adobe-prefix"
runtime_cache="$installer_dir/cache/runtime"
ui_step 2 6 "Pinned Proton and UMU runtime"
runtime_env="$work_root/runtime.env"
"$installer_dir/lib/bootstrap-runtime.sh" "$runtime_cache" >"$runtime_env"
# Generated by the version- and hash-pinned runtime bootstrap.
# shellcheck disable=SC1090,SC1091,SC2153
. "$runtime_env"
proton="${ANIMATE_PROTON_ROOT:-$PROTON_ROOT}"
umu_launcher="${UMU_LAUNCHER:?runtime bootstrap did not return UMU_LAUNCHER}"
umu_bin="$(dirname "$umu_launcher")"
export PATH="$umu_bin:$PATH"
export XDG_DATA_HOME="$work_root/runtime/xdg-data"
export UMU_RUNTIME_UPDATE=0
"$installer_dir/lib/bootstrap-steamrt4.sh" \
    "$runtime_cache/downloads" "$XDG_DATA_HOME/umu"

if [[ "$action" == phase2 ]]; then
    [[ -f "$state_root/adobe-prefix.path" ]] ||
        die "phase 1 state is missing; run --phase1 first"
    adobe_prefix="$(<"$state_root/adobe-prefix.path")"
    [[ -f "$adobe_prefix/$animate_relative" ]] ||
        die "the phase-1 prefix no longer contains Animate.exe"
else
case "$source_mode" in
    prefix|private-template)
        [[ -f "$source_path/$animate_relative" ]] ||
            die "Animate.exe is not present in the supplied prefix"
        adobe_prefix="$source_path"
        ;;
    official-cache|official-download)
        [[ -x "$proton/proton" ]] ||
            die "GE-Proton11-1 not found; set ANIMATE_PROTON_ROOT"
        for required in curl 7z xz unzip cabextract x86_64-w64-mingw32-gcc umu-run; do
            command -v "$required" >/dev/null 2>&1 ||
                die "required command is missing: $required"
        done
        ui_step 3 6 "Official Adobe downloads"
        ANIMATE_ADOBE_CACHE="$official_cache" \
            "$installer_dir/fetch-official-packages.sh" --language "$language" |
            tee "$work_root/logs/adobe-fetch.log"
        # Generated by the hash-verified fetcher; values contain fixed locale
        # identifiers and archive basenames only.
        # shellcheck disable=SC1090,SC1091
        . "$official_cache/selection.env"
        printf 'LANGUAGE_PACKAGE=%q\n' "$ANIMATE_LANGUAGE_PACKAGE" \
            >>"$state_root/source.env"

        cc_directory="$work_root/cc-package"
        if [[ ! -f "$cc_directory/packages/ApplicationInfo.xml" ]]; then
            [[ ! -e "$cc_directory" ]] ||
                die "incomplete Creative Cloud extraction exists: $cc_directory"
            mkdir -p "$cc_directory.partial"
            unzip -q "$cc_archive" -d "$cc_directory.partial"
            mv "$cc_directory.partial" "$cc_directory"
        fi
        core_decoded="$work_root/decoded-core"
        if [[ ! -f "$core_decoded/AppFiles/Animate.exe" ]]; then
            [[ ! -e "$core_decoded" ]] ||
                die "incomplete core decode exists: $core_decoded"
            say "Decoding Animate core payload"
            "$installer_dir/lib/extract-adobe-package.sh" \
                "$official_cache/AdobeAnimate24.0-mul.zip" "$core_decoded"
        fi
        language_decoded="$work_root/decoded-$ANIMATE_LANGUAGE_PACKAGE"
        if [[ ! -d "$language_decoded/AppFiles" ]]; then
            [[ ! -e "$language_decoded" ]] ||
                die "incomplete language decode exists: $language_decoded"
            say "Decoding language payload: $ANIMATE_REQUESTED_LOCALE"
            "$installer_dir/lib/extract-adobe-package.sh" \
                "$official_cache/$ANIMATE_LANGUAGE_ARCHIVE" "$language_decoded"
        fi
        gdiplus="$work_root/dependencies/gdiplus.dll"
        if [[ ! -f "$gdiplus" ]]; then
            say "Acquiring verified Microsoft GDI+"
            "$installer_dir/lib/acquire-gdiplus.sh" \
                "$work_root/cache/microsoft" "$gdiplus"
        fi
        webview2="${ANIMATE_WEBVIEW2_SOURCE:-$work_root/dependencies/webview2}"
        if [[ -z "${ANIMATE_WEBVIEW2_SOURCE:-}" &&
              ! -f "$webview2/msedgewebview2.exe" ]]; then
            say "Acquiring verified Microsoft WebView2 Fixed Version runtime"
            "$installer_dir/lib/acquire-webview2.sh" \
                "$work_root/cache/microsoft-webview2" "$webview2"
        fi
        if [[ ! -f "$adobe_prefix/$animate_relative" ]]; then
            [[ ! -e "$adobe_prefix" ]] ||
                die "incomplete Adobe prefix exists: $adobe_prefix"
            ui_step 4 6 "Building the Animate prefix"
            ANIMATE_WEBVIEW2_SOURCE="$webview2" \
            "$installer_dir/lib/build-official-prefix.sh" \
                "$proton" "$cc_directory" "$core_decoded" "$language_decoded" \
                "$gdiplus" "$adobe_prefix"
        fi
        if [[ ! -f "$adobe_prefix/drive_c/windows/system32/mfc140u.dll" ]]; then
            say "Installing verified Microsoft VC++ 2015-2022 runtime"
            "$installer_dir/lib/install-vcrun2022.sh" \
                "$adobe_prefix" "$proton" "$work_root/cache/vcrun2022"
        fi
        ;;
esac

if [[ "$source_mode" == official-cache ||
      "$source_mode" == official-download ]]; then
    app_dir="$adobe_prefix/drive_c/Program Files/Adobe/Adobe Animate 2024"
    [[ "$(sha256sum "$app_dir/Animate.exe" | awk '{print $1}')" == \
       2f883658cd4691a705af370206ddc7e8a7c12457c0db9102b53e5afde3afe777 ]] ||
        die "phase-1 Animate.exe is not the frozen 24.0.13.5 build"
    [[ "$(sha256sum "$app_dir/dvaui.dll" | awk '{print $1}')" == \
       89654093e3fc0fd2031ab1542573adae1667e3433afd7b66b6447e6e4604b9b8 ]] ||
        die "phase-1 dvaui.dll is not the clean frozen build"
    [[ "$(sha256sum "$adobe_prefix/drive_c/windows/system32/gdiplus_real.dll" |
        awk '{print $1}')" == \
       980ea189929d95eb36e35980fff0c81f7b78de9422771fde8f4ac7a779f5bd89 ]] ||
        die "phase-1 GDI+ backend is unsupported"
    [[ -f "$app_dir/version.dll" &&
       "$(sha256sum "$app_dir/version_real.dll" | awk '{print $1}')" == \
       ec2f7ef63703b1afc3511968b97fc322a401f5c9d6f70d3a3b512feb48078a3c ]] ||
        die "phase-1 COM/MTA proxy backend is incomplete"
    [[ -f "$adobe_prefix/drive_c/windows/system32/mfc140u.dll" &&
       -f "$adobe_prefix/drive_c/windows/syswow64/mfc140u.dll" ]] ||
        die "phase-1 Microsoft VC++ 2015-2022 runtime is incomplete"
    grep -Fq '[Software\\Wine\\Credential Manager\\Generic: Adobe' \
        "$adobe_prefix/user.reg" &&
        die "public phase-1 prefix unexpectedly contains Adobe credentials"
    webview="$adobe_prefix/drive_c/Program Files/Common Files/Adobe/Microsoft/EdgeWebView"
    webview_version="$(<"$adobe_prefix/ANIMATE_WEBVIEW2_VERSION.txt")"
    [[ -L "$webview/Application/$webview_version" &&
       -f "$webview/Application/$webview_version/msedgewebview2.exe" ]] ||
        die "phase-1 WebView2 version mapping is incomplete"
    grep -Fq '[Software\\Wow6432Node\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}]' \
        "$adobe_prefix/system.reg" ||
        die "phase-1 WebView2 registry entry is missing"
fi

printf '%s\n' "$adobe_prefix" >"$state_root/adobe-prefix.path"
touch "$state_root/adobe-prefix.ok"
say "Adobe prefix validated: $adobe_prefix"
fi

if [[ ! -f "$XDG_DATA_HOME/umu/umu-shim" ]]; then
    say "Initialising pinned UMU launcher state"
    (
        export WINEPREFIX="$adobe_prefix"
        export PROTONPATH="$proton"
        export GAMEID=umu-animate-runtime-bootstrap
        export STORE=none PROTON_USE_XALIA=0 WINEDEBUG=-all
        umu-run cmd.exe /c exit
    ) | tee "$work_root/logs/umu-runtime-bootstrap.log"
fi
[[ -x "$XDG_DATA_HOME/umu/steamrt4/run" &&
   -f "$XDG_DATA_HOME/umu/umu-shim" ]] ||
    die "UMU SteamRT4 runtime initialisation failed"

segoe_source="${ANIMATE_SEGOE_SOURCE:-}"
shared_candidate="$(cd -- "$installer_dir/../.." && pwd -P)/Segoe-UI-Font-Family.zip"
if [[ -z "$segoe_source" && -f "$shared_candidate" ]]; then
    segoe_source="$shared_candidate"
fi
if [[ -n "$segoe_source" ]]; then
    say "Installing optional verified Segoe UI family"
    "$installer_dir/lib/install-segoe-ui.sh" \
        "$adobe_prefix" "$proton" "$segoe_source" |
        tee "$work_root/logs/segoe-ui-install.log"
fi

if [[ "$action" == phase1 ]]; then
    exit 0
fi

# Once the prefix has passed every integrity check, decoded Adobe payloads and
# acquisition scratch files are no longer needed. Removing them before the
# final relocatable copy materially lowers peak disk use. They are deliberately
# retained after a failure so a retry can resume without repeating completed
# work.
if (( ! keep_build_cache )) &&
   [[ "$action" == all &&
      "$source_mode" != prefix &&
      "$source_mode" != private-template ]]; then
    say "Reclaiming validated build intermediates"
    rm -rf -- \
        "$work_root/cc-package" \
        "$work_root/decoded-core" \
        "$work_root/decoded-$ANIMATE_LANGUAGE_PACKAGE" \
        "$work_root/dependencies" \
        "$work_root/cache"
fi

if [[ -e "$install_root" ]]; then
    if [[ -x "$install_root/verify.sh" ]] &&
        "$install_root/verify.sh" >/dev/null 2>&1; then
        say "Final installation already exists and verifies successfully"
        touch "$state_root/deploy.ok" "$state_root/final-verify.ok"
        exit 0
    fi
    if [[ -d "$install_root" ]] &&
       [[ -z "$(find "$install_root" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        rmdir "$install_root"
    else
        die "destination exists but is not a verified installation: $install_root"
    fi
fi

ui_step 5 6 "Applying Linux compatibility patches"
ANIMATE_PROTON_ROOT="$proton" \
ANIMATE_UMU_ROOT="$XDG_DATA_HOME/umu" \
ANIMATE_UMU_LAUNCHER="$umu_launcher" \
"$installer_dir/apply-deploy.sh" "$adobe_prefix" "$install_root" |
    tee "$work_root/logs/apply-deploy.log"
touch "$state_root/deploy.ok"
"$install_root/verify.sh"
touch "$state_root/final-verify.ok"
mkdir -p "$config_root" "$records_root"
install_id="animate2024-$(date -u +%Y%m%dT%H%M%SZ)-$(printf '%06x' "$((RANDOM * RANDOM % 16777216))")"
deploy_commit="$(git -C "$installer_dir/.." rev-parse HEAD 2>/dev/null || printf unknown)"
write_install_record()
{
    printf 'format_version=1\n'
    printf 'install_id=%s\n' "$install_id"
    printf 'installed_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'install_root=%s\n' "$install_root"
    printf 'deploy_commit=%s\n' "$deploy_commit"
}
write_install_record >"$install_record"
write_install_record >"$records_root/$install_id.conf"
write_install_record >"$install_root/manifests/managed-install.conf"
chmod 0600 "$install_record"
chmod 0600 "$records_root/$install_id.conf"

cat >"$install_root/INSTALLATION-LOCATIONS.log" <<EOF
Adobe Animate 2024 for Linux - managed installation locations
================================================================
Format version: 1
Installation ID: $install_id
Installed at (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)
Deploy commit: $deploy_commit

COMPLETE RELOCATABLE INSTALLATION
Installation root: $install_root
Adobe/Wine prefix: $install_root/app/prefix
Animate executable: $install_root/app/prefix/drive_c/Program Files/Adobe/Adobe Animate 2024/Animate.exe
GE-Proton runtime: $install_root/runtime/GE-Proton11-1
UMU runtime data: $install_root/runtime/xdg-data/umu
Compatibility binaries: $install_root/support
Launcher: $install_root/launch-animate2024.sh
Diagnostic tool: $install_root/diagnose.sh
Runtime logs: $install_root/logs
Integrity manifests: $install_root/manifests

EXTERNAL USER METADATA
Primary installation record: $install_record
Installation-specific record: $records_root/$install_id.conf
Installer session logs: $state_home/logs

BUILD SOURCE AND TEMPORARY DATA
Installer source used: $installer_dir
Build workspace: $work_root
Download cache: $installer_dir/cache
Build files retained after success: $([[ "$keep_build_cache" == 1 ]] && printf yes || printf no)

HOST CHANGES
On Debian-family systems the installer enables the i386 architecture and
installs the host packages required by UMU/Proton, X11 input, Vulkan/OpenGL,
archive extraction, and compilation of the compatibility proxy. These shared
system packages are intentionally not removed when Animate is uninstalled.

SUPPORTED UNINSTALL COMMAND
From the installer Git clone:
  ./installer/install.sh --uninstall

If the user metadata was deleted:
  ./installer/install.sh --uninstall --install-dir "$install_root"

MANUAL REMOVAL
Delete the complete installation root shown above, then delete the two matching
records under the EXTERNAL USER METADATA section. Installer session logs may
also be deleted. Do not remove shared system packages merely to uninstall
Animate.
EOF

if (( ! keep_build_cache )) && [[ "$action" == all ]]; then
    say "Removing successful build workspace and download cache"
    rm -rf -- \
        "$work_root" \
        "$installer_dir/cache/runtime" \
        "$installer_dir/cache/adobe-official"
fi

ui_step 6 6 "Installation complete"
ui_success "Animate 2024 is ready."
ui_key "Installation" "$install_root"
ui_key "Registry" "$install_record"
ui_key "ID" "$install_id"
printf 'Launch with:\n  %q\n' "$install_root/launch-animate2024.sh"
printf 'Software-rendering fallback:\n  ANIMATE_GPU_MODE=safe %q\n' \
    "$install_root/launch-animate2024.sh"
cp -- "$session_log" "$install_root/INSTALLATION.log"

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -d "$script_dir/app" && -d "$script_dir/runtime" ]]; then
    root="$script_dir"
else
    root="$(cd -- "$script_dir/.." && pwd -P)"
fi
prefix="$root/app/prefix"
proton="$root/runtime/GE-Proton11-1"
umu_data="$root/runtime/xdg-data"
winex11="$proton/files/lib/wine/x86_64-unix/winex11.so"
expected_winex11="1fb4c880c8980fdbaad1b320ecc6866ce0ab30695fbe6b9d6e257a44088cadcf"
animate_exe="$prefix/drive_c/Program Files/Adobe/Adobe Animate 2024/Animate.exe"
p11="$root/support/p11-properties-a2"
mkdir -p "$root/logs"
launch_log="$root/logs/launch-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"
exec > >(tee -a "$launch_log") 2>&1
printf 'Animate launch log: %s\n' "$launch_log"

die()
{
    printf 'ERREUR: %s\n' "$*" >&2
    exit 1
}

[[ -f "$animate_exe" ]] || die "Animate.exe absent du pack."
[[ -x "$proton/proton" ]] || die "GE-Proton11-1 absent du pack."
[[ -f "$winex11" ]] || die "winex11.so P10 absent du runtime."
actual="$(sha256sum "$winex11" | awk '{print $1}')"
[[ "$actual" == "$expected_winex11" ]] ||
    die "winex11.so inattendu ($actual), P10 attendu ($expected_winex11)."
declare -A p11_hashes=(
    [wineserver]="abc2e20a5253decc49e4910f0991f01aac693061056e671137efde77355d05f5"
    [gdiplus.dll]="98353f573e3eb475a597bb4a3b01a5f49e35e721bf8fd5ab4040a604fbee72af"
    [win32u.so]="5e78b4fda2481cc6cbffbb7ae4f4b8fa32528a384865a0bc3471185da1cd1d5b"
    [kernelbase.dll]="b87c2fec5558d4ce4d53a2ff2c912aff1ceea99bf5e58c8dd05e7bfd0251de57"
    [dvaui.dll]="a2ba92552431b9733363936cb4f6b0ac4e08a356f3acfaf184323a3985a9f871"
)
for module in "${!p11_hashes[@]}"; do
    [[ -f "$p11/$module" ]] || die "module P11 absent: $p11/$module"
    actual="$(sha256sum "$p11/$module" | awk '{print $1}')"
    [[ "$actual" == "${p11_hashes[$module]}" ]] ||
        die "module P11 inattendu: $module ($actual)"
done
if [[ -x "$root/runtime/umu-launcher/umu-run" ]]; then
    umu_run="$root/runtime/umu-launcher/umu-run"
elif command -v umu-run >/dev/null 2>&1; then
    umu_run="$(command -v umu-run)"
else
    die "umu-run manque. Exécuter ./install-host-deps.sh puis réessayer."
fi

# Le préfixe Proton contient des liens absolus vers les DLL ICU et les polices
# du runtime qui l'a créé. Les recalculer à chaque lancement rend le dossier
# intégralement relocalisable, même après une copie vers un autre utilisateur.
while IFS= read -r -d '' link; do
    old_target="$(readlink "$link")"
    case "$old_target" in
        *"/GE-Proton11-1/"*)
            suffix="${old_target#*/GE-Proton11-1/}"
            ln -sfn "$proton/$suffix" "$link"
            ;;
    esac
done < <(find "$prefix" -type l -print0)
ln -sfn "$HOME" "$prefix/dosdevices/x:"

export GAMEID=umu-animate
export STORE=none
export PROTONPATH="$proton"
export WINEPREFIX="$prefix"
export XDG_DATA_HOME="$umu_data"
export UMU_RUNTIME_UPDATE=0
# Les chemins sous /mnt et les montages virtiofs ne sont pas exportés
# automatiquement par pressure-vessel. Exposer explicitement le pack complet.
export PRESSURE_VESSEL_FILESYSTEMS_RW="${PRESSURE_VESSEL_FILESYSTEMS_RW:+${PRESSURE_VESSEL_FILESYSTEMS_RW}:}$root"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
export WEBVIEW2_BROWSER_EXECUTABLE_FOLDER='C:\Program Files\Common Files\Adobe\Microsoft\EdgeWebView'
vcrun_overrides='concrt140=n,b;msvcp140=n,b;msvcp140_1=n,b;msvcp140_2=n,b;msvcp140_atomic_wait=n,b;msvcp140_codecvt_ids=n,b;vcamp140=n,b;vccorlib140=n,b;vcomp140=n,b;vcruntime140=n,b;vcruntime140_1=n,b;mfc140=n;mfc140u=n;mfcm140=n;mfcm140u=n'
export WINEDLLOVERRIDES="${ANIMATE_WINEDLLOVERRIDES:-gdiplus=n;wintab32=n;version=n,b;msxml3=b;$vcrun_overrides}"
export WINEDEBUG="${WINEDEBUG:--all}"
export PROTON_USE_XALIA="${PROTON_USE_XALIA:-0}"
export ANIMATE_INPUT_TRACE=0
export ANIMATE_PRESERVE_DRAG_MOVES=1
export ANIMATE_SWP_DEDUP=1
export ANIMATE_FILE_ATTR_CACHE=1

gpu_mode="${ANIMATE_GPU_MODE:-native}"
case "$gpu_mode" in
    safe)
        export DXVK_FILTER_DEVICE_NAME="${ANIMATE_DXVK_DEVICE:-llvmpipe}"
        ;;
    native)
        if [[ -n "${ANIMATE_DXVK_DEVICE:-}" ]]; then
            export DXVK_FILTER_DEVICE_NAME="$ANIMATE_DXVK_DEVICE"
        else
            unset DXVK_FILTER_DEVICE_NAME
        fi
        ;;
    auto)
        # Compatibility alias for older launch commands. Hardware acceleration
        # is the default; no GPU model is blacklisted globally.
        renderer=""
        if command -v glxinfo >/dev/null 2>&1; then
            renderer="$(glxinfo -B 2>/dev/null |
                sed -n 's/^OpenGL renderer string: //p' | head -1)"
        fi
        if [[ -n "${ANIMATE_DXVK_DEVICE:-}" ]]; then
            export DXVK_FILTER_DEVICE_NAME="$ANIMATE_DXVK_DEVICE"
            printf 'GPU DXVK explicite: %s\n' "$DXVK_FILTER_DEVICE_NAME" >&2
        else
            unset DXVK_FILTER_DEVICE_NAME
            printf 'GPU session: %s — accélération matérielle. Utiliser ANIMATE_GPU_MODE=safe si New Document est noir.\n' \
                "${renderer:-inconnu}" >&2
        fi
        ;;
    *)
        die "ANIMATE_GPU_MODE doit valoir auto, safe ou native."
        ;;
esac

if [[ -x "$root/bin/bwrap-nofonts" ]]; then
    export ANIMATE_PACK_ROOT="$root"
    export PRESSURE_VESSEL_BWRAP="$root/bin/bwrap-nofonts"
fi

if [[ -z "${XWINTAB_DEVICE:-}" ]] && command -v xinput >/dev/null 2>&1; then
    XWINTAB_DEVICE="$(xinput list --name-only 2>/dev/null |
        grep -i '^HUION' | grep -F '(0)' | head -1 || true)"
    if [[ -z "$XWINTAB_DEVICE" ]]; then
        XWINTAB_DEVICE="$(
            xinput list --name-only 2>/dev/null | grep -vi 'pad$' |
            while IFS= read -r dev; do
                id="$(xinput list --id-only "$dev" 2>/dev/null)" || continue
                if xinput list --long "$id" 2>/dev/null | grep -q 'Abs Pressure'; then
                    printf '%s\n' "$dev"
                    break
                fi
            done
        )"
    fi
fi
if [[ -n "${XWINTAB_DEVICE:-}" ]]; then
    export XWINTAB_DEVICE
    export XWINTAB_LOG='C:\xwintab.log'
fi

if [[ -x "$root/support/recover_dialog_watcher.sh" ]]; then
    RECOVER_WATCHER_LOG="$root/logs/recover_watcher.log" \
        setsid "$root/support/recover_dialog_watcher.sh" </dev/null >/dev/null 2>&1 &
fi

# Fournir le chemin Unix réel permet à UMU d'identifier le montage contenant le
# pack et de l'exporter dans pressure-vessel (indispensable sous /mnt/virtiofs).
exec "$umu_run" "$animate_exe"

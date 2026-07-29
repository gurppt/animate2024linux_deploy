#!/usr/bin/env bash
set -euo pipefail

if [[ ! -r /etc/os-release ]]; then
    echo "Distribution non détectée. Installer umu-launcher, xdotool, wmctrl, xinput, Vulkan 64/32 bits." >&2
    exit 1
fi
. /etc/os-release
case "${ID:-}" in
    pop|ubuntu|debian)
        echo "Dépendances recommandées (l'installateur les gère automatiquement) :"
        echo "sudo dpkg --add-architecture i386"
        echo "sudo apt update"
        echo "sudo apt install python3 curl tar p7zip-full xz-utils unzip cabextract mingw-w64 bubblewrap xdotool wmctrl xinput mesa-utils vulkan-tools libgl1-mesa-dri:i386 libvulkan1:i386"
        ;;
    fedora)
        echo "Installer Python, curl, tar, p7zip, xz, unzip, cabextract, mingw-w64, bubblewrap, xdotool, wmctrl, xorg-x11-server-utils, glx-utils, vulkan-tools et les pilotes Vulkan 32 bits adaptés au GPU."
        ;;
    arch|manjaro)
        echo "Installer Python, curl, tar, p7zip, xz, unzip, cabextract, mingw-w64, bubblewrap, xdotool, wmctrl, xorg-xinput, mesa-utils, vulkan-tools et lib32-vulkan-icd-loader."
        ;;
    *)
        echo "Distribution ${ID:-inconnue} : installer umu-launcher, xdotool, wmctrl, xinput, OpenGL et Vulkan 64/32 bits."
        ;;
esac
echo
echo "Ce script n'installe rien automatiquement."

#!/usr/bin/env bash

# Small dependency-free terminal UI. Colours are disabled when stdout is not a
# terminal or when NO_COLOR is set.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    UI_RESET=$'\033[0m'
    UI_BOLD=$'\033[1m'
    UI_BLUE=$'\033[38;5;39m'
    UI_CYAN=$'\033[38;5;45m'
    UI_GREEN=$'\033[38;5;40m'
    UI_YELLOW=$'\033[38;5;214m'
    UI_RED=$'\033[38;5;196m'
    UI_DIM=$'\033[2m'
else
    UI_RESET='' UI_BOLD='' UI_BLUE='' UI_CYAN=''
    UI_GREEN='' UI_YELLOW='' UI_RED='' UI_DIM=''
fi

ui_banner()
{
    printf '\n%s%s╭──────────────────────────────────────────────╮%s\n' \
        "$UI_BOLD" "$UI_BLUE" "$UI_RESET"
    printf '%s%s│       Adobe Animate 2024 · Linux setup       │%s\n' \
        "$UI_BOLD" "$UI_BLUE" "$UI_RESET"
    printf '%s%s╰──────────────────────────────────────────────╯%s\n\n' \
        "$UI_BOLD" "$UI_BLUE" "$UI_RESET"
}

ui_step()
{
    printf '\n%s%s[%s/%s]%s %s%s%s\n' "$UI_BOLD" "$UI_BLUE" "$1" "$2" \
        "$UI_RESET" "$UI_BOLD" "$3" "$UI_RESET"
}

ui_info()    { printf '%sℹ%s  %s\n' "$UI_CYAN" "$UI_RESET" "$*"; }
ui_success() { printf '%s✓%s  %s\n' "$UI_GREEN" "$UI_RESET" "$*"; }
ui_warn()    { printf '%s!%s  %s\n' "$UI_YELLOW" "$UI_RESET" "$*"; }
ui_error()   { printf '%s✗%s  %s\n' "$UI_RED" "$UI_RESET" "$*" >&2; }
ui_key()
{
    printf '  %s%-15s%s %s\n' "$UI_DIM" "$1" "$UI_RESET" "$2"
}

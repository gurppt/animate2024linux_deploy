#!/usr/bin/env bash
# recover_dialog_watcher.sh — surface la modale de récupération de crash d'Animate.
#
# PROBLEME (Wine, VM) : au démarrage après un crash, Animate affiche une modale
# "auto-recover file detected / open this file? [Yes][No]" MAIS elle reste ENTERRÉE
# derrière le splash "Building Workspace" (fenêtres override-redirect que le WM ne
# peut pas restacker) => l'app parait FIGÉE (~24 threads, cf. brief §7).
#
# FIX (prouvé 2026-07-24) : détecter la modale, unmapper les fenêtres splash
# override-redirect qui la couvrent, puis remonter la modale au 1er plan. L'utilisateur
# clique alors Yes/No normalement (récupération native préservée). Le boot reprend et
# se termine (~95 threads). AUCUN octet Adobe/Wine modifié — pur window-management X.
#
# Lancé en tâche de fond par launch.sh ; auto-terminé après le boot.
set -u
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
LOG="${RECOVER_WATCHER_LOG:-$HOME/softs/animate2024_wine/logs/recover_watcher.log}"
mkdir -p "$(dirname "$LOG")"
log(){ echo "[$(date +%T)] $*" >>"$LOG"; }
log "watcher démarré (pid $$)"

# dimensions typiques de la modale de récup / message-box Animate
is_dialog(){ # $1=winid -> vrai si taille ~ boîte de dialogue
  local g; g=$(xdotool getwindowgeometry --shell "$1" 2>/dev/null) || return 1
  local WIDTH=0 HEIGHT=0; eval "$g" 2>/dev/null || return 1
  [ "${WIDTH:-0}" -ge 380 ] && [ "${WIDTH:-0}" -le 600 ] && [ "${HEIGHT:-0}" -ge 200 ] && [ "${HEIGHT:-0}" -le 360 ]
}

unmap_splashes(){ # $1=id modale à préserver. Unmap les splash Animate qui couvrent le centre.
  local keep="${1:-}" id w h st
  for id in $(xdotool search --class "steam_app_animate" 2>/dev/null); do
    [ "$id" = "$keep" ] && continue
    # convertir keep (hex 0x..) vs id (décimal xdotool) : comparer en décimal
    [ -n "$keep" ] && [ "$id" = "$((keep))" ] && continue
    # W and H are assigned by the trusted --shell output evaluated below.
    # shellcheck disable=SC2034
    local g W=0 H=0; g=$(xdotool getwindowgeometry --shell "$id" 2>/dev/null) || continue
    eval "$g" 2>/dev/null || continue
    w=${WIDTH:-0}; h=${HEIGHT:-0}
    # splash = large & haut, PAS la fenêtre principale (>=1200), PAS la modale (<=360h), PAS les tiny
    if [ "$w" -ge 300 ] && [ "$w" -lt 1200 ] && [ "$h" -ge 300 ] && [ "$h" -le 900 ]; then
      st=$(xwininfo -id "$id" 2>/dev/null | grep -c "IsViewable")
      [ "$st" -ge 1 ] && xdotool windowunmap "$id" 2>/dev/null && log "splash unmap $id (${w}x${h})"
    fi
  done
  return 0
}

surface(){ # $1=modale : unmap splashs + remonter
  unmap_splashes "$1"
  wmctrl -ir "$1" -b add,above 2>/dev/null
  wmctrl -ir "$1" -e 0,60,80,-1,-1 2>/dev/null
  xdotool windowraise "$1" 2>/dev/null
  wmctrl -ia "$1" 2>/dev/null
  xdotool windowfocus "$1" 2>/dev/null
  log "modale $1 surfacée"
}

deadline=$(( $(date +%s) + 150 ))
handled=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  pgrep -x Animate.exe >/dev/null 2>&1 || { sleep 1; continue; }
  while read -r id; do
    [ -z "$id" ] && continue
    [ "$id" = "$handled" ] && continue
    if is_dialog "$id"; then
      log "modale candidate détectée: $id"
      surface "$id"; handled="$id"
      # re-surfacer tant que la modale existe (au cas où le splash se re-mappe)
      for _ in $(seq 1 8); do
        xwininfo -id "$id" >/dev/null 2>&1 || { log "modale $id fermée (répondu)"; break; }
        surface "$id"; sleep 2
      done
    fi
  done < <(wmctrl -l 2>/dev/null | awk '{print $1}')
  sleep 1
done
log "watcher terminé"

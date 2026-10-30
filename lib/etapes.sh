#!/bin/bash
# pxl-bootsplash-etapes — les étapes du démarrage sur l'écran PXL (thème Plymouth « pxl »), pxl-bootsplash-etapes.service.
# Repris de la box PXL GFX (demarrage-etapes.sh, 02/10/2026), rendu générique le 30/10/2026 : les étapes ne sont plus
# écrites ici, l'APPAREIL les déclare dans /etc/pxl-bootsplash/appareil.conf (ETAPES=…), et chacune est une SONDE :
#   /etc/pxl-bootsplash/sondes/<nom>.sh  (propre à l'appareil, prioritaire)  ou  /usr/lib/pxl-bootsplash/sondes/<nom>.sh
# Une sonde définit LIBELLE="…" et une fonction `sonde` qui imprime « ÉTAT|détail » (0 attente · 1 en cours · 2 fait ·
# 3 défaut · 4 avertissement). Elle LIT l'état réel de la machine — jamais un délai ni une supposition.
# Toutes les demi-secondes chaque étape est relue, et envoyée à Plymouth seulement si elle a changé.
#
# ⭐ La FIN de l'écran de démarrage, en deux temps (pxl-bootsplash-lacher) :
#   1. avant de démarrer, le programme d'affichage fait LÂCHER le DRM à Plymouth (`plymouth deactivate`) : l'image de
#      Plymouth reste balayée, le programme prend la carte sans écran noir ni changement de mode ;
#   2. ICI, quand le programme a posé sa première image — il crée $TEMOIN (variable PXL_BOOTSPLASH_TEMOIN, donnée par
#      son complément systemd) —, `plymouth quit`. Le tampon de Plymouth n'est plus balayé : le retirer ne coupe rien.
#   🔴 Pas de sonde de la carte DRM pendant ce passage : entre `deactivate` et l'ouverture par le programme, il n'y a
#   AUCUN maître, et le premier qui ouvre /dev/dri/card0 le devient — si c'était nous, le programme (non root) ne
#   pourrait plus le prendre.
#   Sans signal en $FIN_S secondes : `plymouth quit` quand même (dit dans le journal : ce cas peut noircir l'écran).
#   Si le programme s'arrête entre les deux : Plymouth REPREND l'écran et le dit (systemd le relance).
# S'arrête quand Plymouth n'est plus là, et au plus tard après $DUREE_MAX s de démarrage.
# ⭐ 1.1.0 — `--arret` (pxl-bootsplash-arret.service, à l'arrêt et au redémarrage) : les étapes d'ETAPES_ARRET, et
# l'avancement de la barre (« pxl|B|c| ») = la part des services déjà arrêtés. Ni plafond de durée (la machine tourne
# depuis longtemps), ni passage de main : il tourne jusqu'à ce que systemd-shutdown l'arrête.
CONF=${PXL_BOOTSPLASH_CONF:-/etc/pxl-bootsplash/appareil.conf}
LIB=${PXL_BOOTSPLASH_LIB:-/usr/lib/pxl-bootsplash}
RUN=${PXL_BOOTSPLASH_RUN:-/run/pxl-bootsplash}
SONDES_APPAREIL=/etc/pxl-bootsplash/sondes
ETAPES="systeme"; PRODUIT="PXL"; AFFICHAGE_UNITE=""; FIN_S=90; DUREE_MAX=300
ETAPES_ARRET="arret-demande arret-affichage arret-services arret-fin"
ARRET=0; [ "${1:-}" = --arret ] && ARRET=1
# shellcheck disable=SC1090
. "$CONF" 2>/dev/null || echo "pxl-bootsplash-etapes : $CONF illisible — étapes par défaut"
[ $ARRET = 1 ] && { ETAPES=$ETAPES_ARRET; DUREE_MAX=999999999; }
LACHE=$RUN/lache                   # posé par pxl-bootsplash-lacher : Plymouth a lâché l'écran
TEMOIN=$RUN/signal/premiere-image  # créé par le programme d'affichage : sa première image est balayée

# /run est neuf à chaque démarrage ; le dossier du signal est écrit par le programme d'affichage, qui n'est pas root
mkdir -p "$RUN" && install -d -m 1777 "$RUN/signal"
[ $ARRET = 0 ] && rm -f "$LACHE" "$TEMOIN"

secondes() { cut -d. -f1 /proc/uptime; }
NIVEAUX=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ   # pas l'horloge : sans pile, l'heure saute à la synchronisation
declare -A dernier
envoyer() {   # étape (1-8, F), état (n libellé · 0-4), texte — seulement si ça change
  local m="pxl|$1|$2|$3"
  [ "${dernier[$1]-}" = "$m" ] && return
  dernier[$1]=$m; plymouth update --status="$m" 2>/dev/null
}

# ── les sondes : `sonde` de chaque fichier devient `sonde_<i>`, et son LIBELLE est envoyé une fois
i=0; ORDRE=()
for nom in $ETAPES; do
  [ $i -ge 8 ] && { echo "pxl-bootsplash-etapes : plus de 8 étapes — « $nom » et suivantes ignorées"; break; }
  f=$SONDES_APPAREIL/$nom.sh; [ -f "$f" ] || f=$LIB/sondes/$nom.sh
  [ -f "$f" ] || { echo "pxl-bootsplash-etapes : pas de sonde « $nom » — étape ignorée"; continue; }
  unset -f sonde; LIBELLE=$nom
  # shellcheck disable=SC1090
  . "$f"
  declare -F sonde >/dev/null || { echo "pxl-bootsplash-etapes : $f ne définit pas « sonde »"; continue; }
  i=$((i + 1)); ORDRE+=("$i")
  eval "sonde_$i() $(declare -f sonde | tail -n +2)"
  envoyer "$i" n "$LIBELLE"
  [ "$nom" = "${AFFICHAGE_ETAPE:-}" ] && echo "$i" > "$RUN/etape-affichage" 2>/dev/null
done
if declare -F pied >/dev/null; then envoyer F 0 "$(pied)"; else envoyer F 0 "$(hostname)  ·  $PRODUIT"; fi

lache_a=""
while plymouth --ping 2>/dev/null && [ "$(secondes)" -lt "$DUREE_MAX" ]; do
  t=$(secondes)
  for k in "${ORDRE[@]}"; do
    r=$(sonde_"$k" "$t" 2>/dev/null) || true
    [ -n "$r" ] && envoyer "$k" "${r%%|*}" "${r#*|}"
  done

  # ── à l'arrêt : l'avancement = la part des travaux de systemd déjà faits (36 niveaux, un caractère : pxl.script)
  if [ $ARRET = 1 ]; then
    n=$(systemctl list-jobs --no-legend 2>/dev/null | wc -l)
    [ "$n" -gt "${n0:-0}" ] && n0=$n
    if [ "${n0:-0}" -gt 0 ]; then
      niv=$(( (n0 - n) * 35 / n0 )); envoyer B "${NIVEAUX:niv:1}" ""
    fi
    sleep 0.5; continue
  fi
  # ── la fin de l'écran de démarrage
  if [ -z "$AFFICHAGE_UNITE" ] && systemctl is-active -q multi-user.target; then
    # aucun programme d'affichage déclaré : rien ne le relaiera, Plymouth part une fois le système levé
    sleep 2; plymouth quit 2>/dev/null; break
  elif [ -e "$LACHE" ]; then
    [ -z "$lache_a" ] && lache_a=$t
    if [ -e "$TEMOIN" ]; then
      echo "pxl-bootsplash-etapes : première image du programme d'affichage à ${t} s — Plymouth part"
      plymouth quit 2>/dev/null; break
    elif [ -n "$AFFICHAGE_UNITE" ] && ! systemctl is-active -q "$AFFICHAGE_UNITE" \
         && [ "$(systemctl show -p ActiveState --value "$AFFICHAGE_UNITE")" != activating ]; then
      # arrêté entre « lâché » et sa première image : Plymouth reprend l'écran et le dit ; systemd le relance
      echo "pxl-bootsplash-etapes : $AFFICHAGE_UNITE arrêté avant sa première image — Plymouth reprend l'écran"
      rm -f "$LACHE"; lache_a=""
      plymouth reactivate 2>/dev/null
      e=$(cat "$RUN/etape-affichage" 2>/dev/null); [ -n "$e" ] && envoyer "$e" 3 "arrêté — relance…"
    elif [ $((t - lache_a)) -ge "$FIN_S" ]; then
      echo "pxl-bootsplash-etapes : ⚠️ aucun signal de première image en ${FIN_S} s — Plymouth part quand même" \
           "(son tampon retiré peut noircir l'écran un instant)"
      plymouth quit 2>/dev/null; break
    fi
  fi
  sleep 0.5
done
exit 0

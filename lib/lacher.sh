#!/bin/bash
# pxl-bootsplash-lacher — avant le programme d'affichage (son complément systemd, posé par l'installeur :
# `ExecStartPre=-+/usr/lib/pxl-bootsplash/lacher` — « + » en root, « - » : un échec ne l'empêche JAMAIS de démarrer).
#
# Le programme d'affichage a besoin du DRM que Plymouth tient. Deux façons de le lui rendre (FIN dans appareil.conf) :
#   deactivate (défaut) : Plymouth rend le DRM master SANS partir — son image reste balayée, le programme ouvre la carte
#                         sans maître et la prend, puis pxl-bootsplash-etapes fait partir Plymouth sur le signal de
#                         première image du programme. Aucun écran noir entre les deux, aucun changement de mode.
#   quit                : `plymouth quit --retain-splash`, la façon de la box PXL GFX (Weston, 02/10/2026).
# 🎯 « deactivate » par défaut est DÉDUIT, et à mesurer sur chaque appareil (dmesg « Update mode » + vidéo) : un
#   processus qui part retire ses tampons, et retirer le tampon balayé éteint l'écran (mesuré sur la box le 02/10,
#   pxl-mode.c) — `--retain-splash` ne peut pas l'empêcher sur un noyau 6.1.
# Sans écran de démarrage (relance du programme en cours de journée) : rien à faire, sortie immédiate.
plymouth --ping 2>/dev/null || exit 0
CONF=${PXL_BOOTSPLASH_CONF:-/etc/pxl-bootsplash/appareil.conf}
RUN=${PXL_BOOTSPLASH_RUN:-/run/pxl-bootsplash}
FIN=deactivate
# shellcheck disable=SC1090
. "$CONF" 2>/dev/null
e=$(cat "$RUN/etape-affichage" 2>/dev/null)
[ -n "$e" ] && plymouth update --status="pxl|$e|1|ouverture de l'affichage…" 2>/dev/null
sleep 0.3
mkdir -p "$RUN" && install -d -m 1777 "$RUN/signal"
# ⭐ (1.0.4) LE TÉMOIN, lisible sans voir l'écran (proposé par la session pxl-switcher, 30/10) : ce que porte tty1 et le
# mode du VT, avant et après le passage. tty1 doit être VIDE quand l'écran change de main — fbcon peut le montrer une image.
temoin() {
  local n kd
  n=$(fold -w 400 /dev/vcs1 2>/dev/null | grep -vc '^[[:space:]]*$')
  kd=$(python3 -I -c 'import fcntl,array,sys
a=array.array("i",[0]); f=open("/dev/tty1","rb"); fcntl.ioctl(f,0x4B3B,a); print({0:"texte",1:"graphique"}.get(a[0],a[0]))' 2>/dev/null)
  echo "pxl-bootsplash-lacher : témoin $1 — tty1 : ${n:-?} ligne(s) non vide(s), VT en mode ${kd:-?}" | tee -a "$RUN/temoin"
}
# tty1 (fbcon) ne doit rien montrer si l'écran lui revient un instant : vidé, curseur masqué — avant ET après le passage
vider_tty1() { printf '\033[H\033[2J\033[3J\033[?25l' > /dev/tty1 2>/dev/null; }
temoin "avant"
vider_tty1
temoin "après vidage"
if [ "$FIN" = quit ]; then
  timeout 5 plymouth quit --retain-splash 2>/dev/null
  echo "pxl-bootsplash-lacher : Plymouth parti (--retain-splash)"
elif timeout 5 plymouth deactivate 2>/dev/null; then
  touch "$RUN/lache"
  echo "pxl-bootsplash-lacher : Plymouth a lâché le DRM, son image reste à l'écran"
else
  # 🔴 un Plymouth qui ne lâcherait pas garderait le DRM master : le programme n'aurait pas d'écran. Repli : le renvoyer.
  timeout 5 plymouth quit 2>/dev/null
  echo "pxl-bootsplash-lacher : ⚠️ deactivate sans réponse — Plymouth renvoyé"
fi
vider_tty1   # ce que Plymouth aurait écrit en lâchant le VT
temoin "après le passage"
exit 0

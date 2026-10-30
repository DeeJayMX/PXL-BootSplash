# lib/cmdline.sh — la ligne de commande du noyau voulue par pxl-bootsplash (sourcé par installer.sh et par les tests).
# · `splash` réveille le Plymouth de l'INITRD, qui n'a pas encore de DRM (Rock 5B : le pilote d'affichage n'est prêt qu'à
#   ~5,7 s, après le passage à la racine, mesuré le 30/10) — celui du système suffit, et l'initrd n'est pas touché ;
# · console=tty0/tty1 : le noyau et systemd écrivent sur l'écran (traces `rga_mm`, lignes `[ OK ]` : photo d'Eliott du
#   30/10, arrêt de pxl-tx) — la console série garde tout ;
# · video= passe AVANT le mode préféré de l'EDID (drm_client_modeset) : c'est pxl-bootsplash-mode qui décide.
CMDLINE_RETIRER='^(splash|console=tty[0-9]*|video=.*)$'
CMDLINE_AJOUTER=(quiet plymouth.graphical plymouth.ignore-serial-consoles logo.nologo vt.global_cursor_default=0
  systemd.show_status=false)
# voulue LIGNE : on retire, puis on ajoute ce qui manque — l'ordre des arguments gardés ne bouge pas
voulue() {
  local a x vu out=()
  for a in $1; do [[ $a =~ $CMDLINE_RETIRER ]] || out+=("$a"); done
  for a in "${CMDLINE_AJOUTER[@]}"; do vu=0; for x in "${out[@]}"; do [ "$x" = "$a" ] && vu=1; done; [ $vu = 1 ] || out+=("$a"); done
  echo "${out[*]}"
}
# append_de FICHIER LABEL : la ligne `append` d'un label extlinux
append_de() { awk -v L="$2" '$1=="label"{l=($2==L);next} l && $1=="append"{sub(/^[ \t]*append[ \t]+/,""); print; exit}' "$1" 2>/dev/null; }

# lib/cmdline.sh — la ligne de commande du noyau voulue par pxl-bootsplash (sourcé par installer.sh et par les tests).
# · `splash` réveille le Plymouth de l'INITRD, qui n'a pas encore de DRM (Rock 5B : le pilote d'affichage n'est prêt qu'à
#   ~5,7 s, après le passage à la racine, mesuré le 30/10) — celui du système suffit, et l'initrd n'est pas touché ;
# · console=tty0/tty1 : le noyau et systemd écrivent sur l'écran (traces `rga_mm`, lignes `[ OK ]` : photo d'Eliott du
#   30/10, arrêt de pxl-tx) — la console série garde tout ;
# · video= passe AVANT le mode préféré de l'EDID (drm_client_modeset) : c'est pxl-bootsplash-mode qui décide.
CMDLINE_RETIRER='^(splash|console=tty[0-9]*|video=.*)$'
CMDLINE_AJOUTER=(quiet nosplash rhgb plymouth.graphical plymouth.ignore-serial-consoles plymouth.nolog logo.nologo
  vt.global_cursor_default=0 systemd.show_status=false)
# ⭐ 1.0.4 — `plymouth.nolog` (30/10, vu par Eliott : une image de console au départ du compositeur). Mesuré sur pxl-tx :
#   plymouthd envoie SIGRTMIN+20 à systemd dès son démarrage (4,83 s), ce qui RÉACTIVE l'affichage d'état malgré
#   `systemd.show_status=false`, et il DÉTOURNE la console pour son boot.log : les lignes `[ OK ]` finissaient dans tty1
#   (/dev/vcs1 : 67 lignes), et fbcon les montrait le temps d'une image au passage de main. Sans détournement, elles
#   vont à la console série seule. (Interrupteur lu dans /usr/sbin/plymouthd : « plymouth.nolog ».)
# 🔴 ERRATUM 1.0.3 (30/10, 18h30, mesuré sur pxl-tx) — `plymouth.graphical` NE REMPLACE PAS `splash` ici. Deux faits :
# · le Plymouth de Debian (22.02) n'affiche un thème graphique QUE si la ligne porte `splash` ou `rhgb` — sinon
#   « details », c'est-à-dire le JOURNAL à l'écran (lu dans /usr/sbin/plymouthd : « no default splash because kernel
#   command line lacks "splash" or "rhgb" ») ; la règle venait de la box (Ubuntu, Plymouth 24) : un autre objet ;
# · le script de l'initrd de Debian démarre Plymouth PAR DÉFAUT (`SPLASH="true"`, seul `nosplash` l'éteint) — c'est
#   lui, avec le thème de l'initrd, qui tenait l'écran, et le nôtre n'était jamais chargé.
# ⇒ `nosplash` : pas de Plymouth dans l'initrd (et l'initrd n'est toujours pas touché) ; `rhgb` : celui du système est
#   graphique ; plymouth-start.service.d/10-pxl-bootsplash.conf lui retire sa condition `!nosplash`.
# 🔴 Et la première ligne ci-dessus se trompe aussi : le DRM n'est pas prêt « à ~5,7 s, après le passage à la racine »
#   — 5,7 s est une heure de `dmesg`, qui a 4,05 s d'avance sur le journal (mesuré) : le mode du noyau est posé vers
#   1,9 s, AVANT l'initrd. Ce n'est donc pas faute de DRM que l'initrd est écarté : c'est pour que NOTRE Plymouth,
#   lancé après la décision de mode, soit le seul.
# voulue LIGNE : on retire, puis on ajoute ce qui manque — l'ordre des arguments gardés ne bouge pas
voulue() {
  local a x vu out=()
  for a in $1; do [[ $a =~ $CMDLINE_RETIRER ]] || out+=("$a"); done
  for a in "${CMDLINE_AJOUTER[@]}"; do vu=0; for x in "${out[@]}"; do [ "$x" = "$a" ] && vu=1; done; [ $vu = 1 ] || out+=("$a"); done
  echo "${out[*]}"
}
# append_de FICHIER LABEL : la ligne `append` d'un label extlinux
append_de() { awk -v L="$2" '$1=="label"{l=($2==L);next} l && $1=="append"{sub(/^[ \t]*append[ \t]+/,""); print; exit}' "$1" 2>/dev/null; }

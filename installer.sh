#!/bin/bash
# installer.sh — POSER pxl-bootsplash SUR UN APPAREIL (30/10/2026).
#
# L'écran de démarrage commun aux appareils PXL : logo, puis les étapes du démarrage que l'APPAREIL déclare, du mode
# posé par le noyau jusqu'à la première image de son programme d'affichage — sans texte, sans curseur, et sans
# changement de mode quand l'écran annonce le sien. Voir README.md.
#
#   sudo ./installer.sh --appareil /chemin/appareil.conf [--sondes DOSSIER]     SIMULATION : dit ce qu'il ferait
#   sudo ./installer.sh --appareil … [--sondes …] --appliquer                    pose
#   sudo ./installer.sh --verifier                                               contrôle seul (lecture seule)
#   sudo ./installer.sh --retirer [--appliquer]                                  défait (simulation sans --appliquer)
# Options :
#   --cmdline extlinux[:LABEL]   règle aussi la ligne de commande du noyau dans /boot/extlinux/extlinux.conf, sous
#                                `label LABEL` (défaut l0), à la main — JAMAIS u-boot-update. Sauvegarde avant.
#   --cmdline non                (défaut) l'appareil gère sa ligne de commande lui-même ; --verifier la contrôle quand
#                                même (/proc/cmdline et le label l0 s'il existe).
#
# 🔒 CE QU'IL NE FAIT JAMAIS : il ne redémarre rien et ne relance aucun service (un écran de démarrage se voit au
# démarrage suivant) ; il ne touche ni à l'initrd ni au chargeur (U-Boot) ; il n'écrase rien sans en garder une copie
# `*.avant-pxl-bootsplash`.
# ⚠️ PAS de `pipefail` (leçon de PXL-Switcher, installer-carte.sh, 26/10) : `… | grep -q` y rend un faux échec.
set -u
ICI=$(cd "$(dirname "$0")" && pwd)
VERSION=$(cat "$ICI/VERSION" 2>/dev/null || echo "?")
MODE=simulation; RETIRER=0; APPAREIL=""; SONDES=""; CMDLINE=non
while [ $# -gt 0 ]; do
  case "$1" in
    --appliquer) MODE=appliquer ;;
    --verifier)  MODE=verifier ;;
    --retirer)   RETIRER=1 ;;
    --appareil)  APPAREIL=$2; shift ;;
    --sondes)    SONDES=$2; shift ;;
    --cmdline)   CMDLINE=$2; shift ;;
    -h|--help)   sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "option inconnue : $1"; exit 2 ;;
  esac; shift
done
[ "$(id -u)" = 0 ] || [ "$MODE" = simulation ] || { echo "🔴 en root (sudo)"; exit 2; }
ETIQUETTE=$(date +%Y%m%d-%H%M%S)

LIB=/usr/lib/pxl-bootsplash; THEME=/usr/share/plymouth/themes/pxl; ETC=/etc/pxl-bootsplash; SD=/etc/systemd/system
ETAT=/var/lib/pxl-bootsplash
PAQUETS=(plymouth plymouth-label fonts-dejavu-core gcc libdrm-dev pkg-config librsvg2-bin)
MASQUES=(plymouth-quit.service plymouth-quit-wait.service)   # sinon Debian ferme Plymouth à multi-user.target (5,6 s)
# shellcheck disable=SC1091
. "$ICI/lib/cmdline.sh"   # CMDLINE_RETIRER, CMDLINE_AJOUTER, voulue, append_de

ROUGES=0; JAUNES=0
titre() { printf '\n=== %s ===\n' "$*"; }
dire()  { printf '  %s\n' "$*"; }
ok()    { printf '  ✅ %s\n' "$*"; }
rouge() { printf '  🔴 %s\n' "$*"; ROUGES=$((ROUGES + 1)); }
jaune() { printf '  ⚠️  %s\n' "$*"; JAUNES=$((JAUNES + 1)); }
faire() {
  if [ "$MODE" = appliquer ]; then printf '  $ %s\n' "$*"; bash -c "$*" || { rouge "échec : $*"; return 1; }
  else printf '  [simulation] %s\n' "$*"; fi
}
# poser SRC DEST MODE — compare d'abord ; jamais en place (un script qui tourne relirait un autre texte) : voisin + mv
poser() {
  local src=$1 dest=$2 mode=${3:-644}
  [ -f "$src" ] || { rouge "source absente : $src"; return 1; }
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then return 0; fi
  if [ "$MODE" = appliquer ]; then
    [ -f "$dest" ] && [ ! -e "$dest.avant-pxl-bootsplash" ] && cp -a "$dest" "$dest.avant-pxl-bootsplash"
    install -D -m "$mode" "$src" "$dest.pxl-neuf" && mv -f "$dest.pxl-neuf" "$dest" && printf '  posé  %s\n' "$dest" \
      || rouge "pose impossible : $dest"
  else printf '  [simulation] %s %s\n' "$([ -f "$dest" ] && echo remplacer || echo poser)" "$dest"; fi
}
# La liste des fichiers posés tels quels : UNE liste, lue par la pose ET par le contrôle.
FICHIERS=(
  "$ICI/lib/etapes.sh|$LIB/etapes|755" "$ICI/lib/lacher.sh|$LIB/lacher|755" "$ICI/lib/mode-demarrage.sh|$LIB/mode-demarrage|755"
  "$ICI/lib/fin-arret.sh|$LIB/fin-arret|755" "$ICI/systemd/pxl-bootsplash-fin-arret.service|$SD/pxl-bootsplash-fin-arret.service|644"
  "$ICI/theme/pxl.plymouth|$THEME/pxl.plymouth|644" "$ICI/theme/pxl.script|$THEME/pxl.script|644"
  "$ICI/systemd/pxl-bootsplash-mode.service|$SD/pxl-bootsplash-mode.service|644"
  "$ICI/systemd/pxl-bootsplash-etapes.service|$SD/pxl-bootsplash-etapes.service|644"
  "$ICI/systemd/pxl-bootsplash-arret.service|$SD/pxl-bootsplash-arret.service|644"
  "$ICI/systemd/plymouth-start.service.d-10-pxl-bootsplash.conf|$SD/plymouth-start.service.d/10-pxl-bootsplash.conf|644"
)
for f in "$ICI"/lib/sondes/*.sh; do FICHIERS+=("$f|$LIB/sondes/$(basename "$f")|644"); done
[ -n "$SONDES" ] && for f in "$SONDES"/*.sh; do FICHIERS+=("$f|$ETC/sondes/$(basename "$f")|644"); done
[ -n "$APPAREIL" ] && FICHIERS+=("$APPAREIL|$ETC/appareil.conf|644")
# le programme d'affichage de l'appareil (lu dans SON appareil.conf : celui qu'on pose, sinon celui qui est posé)
lire_conf() { ( AFFICHAGE_UNITE=""; GETTY_TTY1=couper; . "${APPAREIL:-$ETC/appareil.conf}" 2>/dev/null; eval "echo \"\$$1\"" ); }
AFFICHAGE_UNITE=$(lire_conf AFFICHAGE_UNITE); GETTY_TTY1=$(lire_conf GETTY_TTY1)
[ -n "$AFFICHAGE_UNITE" ] && FICHIERS+=("$ICI/systemd/affichage.d-20-pxl-bootsplash.conf|$SD/$AFFICHAGE_UNITE.d/20-pxl-bootsplash.conf|644")

# plymouthd.conf : rendu ici (une ligne de thème), comparé comme un fichier
PLYCONF=$(mktemp); printf '# pxl-bootsplash %s — thème « pxl », sans délai d’apparition\n[Daemon]\nTheme=pxl\nShowDelay=0\n' "$VERSION" > "$PLYCONF"
FICHIERS+=("$PLYCONF|/etc/plymouth/plymouthd.conf|644")
# ⭐ 1.1.0 — L'ÉCRAN D'ARRÊT : les quatre unités Plymouth d'arrêt de Debian, réveillées (`nosplash` les éteint) et
# ordonnées par rapport au programme d'affichage. Entre une unité qui s'ARRÊTE et une qui DÉMARRE, systemd fait passer
# l'arrêt d'abord quelle que soit la direction de l'ordre (systemd.unit, After=) : Plymouth démarre donc une fois le
# programme parti — il tenait le DRM. Rendu ici : le nom du programme vient de l'appareil.
ARRETS=$(mktemp -d)
for u in reboot poweroff halt kexec; do
  { printf '# pxl-bootsplash %s — écran PXL à l%sarrêt : conditions reposées sans « !nosplash » (la ligne le porte pour
' "$VERSION" "'"
    printf '# éteindre le Plymouth de l%sinitrd), et Plymouth APRÈS le programme d%saffichage, qui tient le DRM.
[Unit]
' "'" "'"
    printf 'ConditionKernelCommandLine=
ConditionKernelCommandLine=!plymouth.enable=0
ConditionVirtualization=!container
'
    [ -n "$AFFICHAGE_UNITE" ] && printf 'After=%s
' "$AFFICHAGE_UNITE"
  } > "$ARRETS/plymouth-$u.conf"
  FICHIERS+=("$ARRETS/plymouth-$u.conf|$SD/plymouth-$u.service.d/10-pxl-bootsplash.conf|644")
done
trap 'rm -rf "$PLYCONF" "$ARRETS"' EXIT

# ═══ LES ÉTAPES : un CONTRÔLE (lecture seule, 0 = fait) et une POSE ═════════════════════════════════════════════════
c_paquets() { local p r=0; for p in "${PAQUETS[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || { r=1; [ "$MODE" = verifier ] && dire "absent : $p"; }; done; return $r; }
p_paquets() { faire "apt-get install -y --no-install-recommends ${PAQUETS[*]}"; }

SRC_MODE=$ICI/src/pxl-bootsplash-mode.c
c_outil() {   # la source posée doit être celle du dépôt (son empreinte), et le binaire doit rendre le GTF du noyau
  [ -x "$LIB/mode" ] || return 1
  [ "$(cat "$LIB/mode.source.sha256" 2>/dev/null)" = "$(sha256sum < "$SRC_MODE" | cut -d' ' -f1)" ] || return 1
  [ "$("$LIB/mode" --gtf 800x480@60)" = "800 816 896 992 480 481 484 497 29605 -hsync +vsync" ]
}
p_outil() {
  faire "mkdir -p $LIB && gcc -O2 -Wall -o $LIB/mode.neuf '$SRC_MODE' \$(pkg-config --cflags --libs libdrm) && mv -f $LIB/mode.neuf $LIB/mode && sha256sum < '$SRC_MODE' | cut -d' ' -f1 > $LIB/mode.source.sha256"
}

c_fichiers() {
  local e src dest r=0
  for e in "${FICHIERS[@]}"; do IFS='|' read -r src dest _ <<< "$e"
    cmp -s "$src" "$dest" 2>/dev/null || { r=1; [ "$MODE" = verifier ] && dire "écart : $dest"; }
  done
  [ -f "$ETC/appareil.conf" ] || { r=1; [ "$MODE" = verifier ] && dire "pas d'appareil.conf (--appareil)"; }
  return $r
}
p_fichiers() {
  [ -n "$APPAREIL" ] || [ -f "$ETC/appareil.conf" ] || { rouge "--appareil FICHIER obligatoire (voir exemples/appareil.conf)"; return 1; }
  local e src dest mode; for e in "${FICHIERS[@]}"; do IFS='|' read -r src dest mode <<< "$e"; poser "$src" "$dest" "$mode"; done
}

# ⭐ 1.1.0 — LES IMAGES, rendues ICI (aucun binaire dans le dépôt) par rsvg-convert : le logo, et pour chaque hauteur
# d'écran courante les éléments du cartouche et de la barre, à la bonne taille — des pixels FRANCS pour la rivière
# (une image de 1080 lignes mise à l'échelle par Plymouth serait floue). Une hauteur absente de la liste reprend celles
# de 1080, mises à l'échelle par le thème.
HAUTEURS=(480 600 720 768 800 1024 1080 1200 1440 2160)
ELEMENTS=(cartouche piste masque tete riviere)
empreinte_images() { cat "$ICI"/theme/*.svg | sha256sum | cut -d' ' -f1; }
c_logo() { [ -s "$THEME/logo.png" ] && [ -s "$THEME/riviere-1080.png" ] && [ "$(cat "$THEME/images.source.sha256" 2>/dev/null)" = "$(empreinte_images)" ]; }
p_logo() {
  # ⭐ rsvg-convert d'abord : la box rendait par Chromium, mais le Chromium de Radxa (Rock 5B) n'a PAS la plateforme
  # headless — « Invalid ozone platform: headless », mesuré sur pxl-tx le 30/10. Chromium reste le repli (logo seul).
  local nav; nav=$(command -v chromium chromium-browser google-chrome 2>/dev/null | head -1)
  if [ "$MODE" != appliquer ]; then dire "[simulation] rendre logo.png et ${#ELEMENTS[@]} éléments × ${#HAUTEURS[@]} hauteurs dans $THEME"; return 0; fi
  local r h e z n=0; r=$(mktemp -d); cp "$ICI/theme/logo-pxl.svg" "$r/"
  if command -v rsvg-convert >/dev/null; then rsvg-convert -w 1400 "$r/logo-pxl.svg" -o "$r/logo.png" || true; fi
  if [ ! -s "$r/logo.png" ] && [ -n "$nav" ]; then
    # ⚠️ en 100vw/100vh, pas en pixels fixes : en --headless=new la zone utile est plus petite que --window-size, et un
    # logo en pixels sortait rogné (box, mesuré le 02/10).
    printf '<!doctype html><style>html,body{margin:0;background:transparent}img{display:block;width:100vw;height:100vh;object-fit:contain}</style><img src="logo-pxl.svg">' > "$r/l.html"
    "$nav" --headless=new --no-sandbox --disable-gpu --hide-scrollbars --default-background-color=00000000 \
      --user-data-dir="$r/profil" --window-size=1400,780 --screenshot="$r/logo.png" "file://$r/l.html" >/dev/null 2>&1 || true
  fi
  if [ -s "$r/logo.png" ]; then install -D -m 644 "$r/logo.png" "$THEME/logo.png" && printf '  posé  %s\n' "$THEME/logo.png"
  else jaune "logo non rendu (ni rsvg-convert ni Chromium) : l'écran montrera « pxl mstrs. » en texte"; fi
  if command -v rsvg-convert >/dev/null; then
    for h in "${HAUTEURS[@]}"; do
      z=$(awk -v h="$h" 'BEGIN{printf "%.6f", h / 1080}')
      for e in "${ELEMENTS[@]}"; do
        rsvg-convert -z "$z" "$ICI/theme/$e.svg" -o "$r/$e-$h.png" && install -D -m 644 "$r/$e-$h.png" "$THEME/$e-$h.png" && n=$((n + 1))
      done
    done
    printf '  posé  %s images (cartouche, piste, masque, tête, rivière × %s hauteurs)\n' "$n" "${#HAUTEURS[@]}"
    empreinte_images > "$THEME/images.source.sha256"
  else jaune "rsvg-convert absent : pas de cartouche ni de barre (le thème s'en passe)"; fi
  rm -rf "$r"
}

UNITES_ON=(pxl-bootsplash-mode.service pxl-bootsplash-etapes.service pxl-bootsplash-arret.service pxl-bootsplash-fin-arret.service)
c_services() {
  local u r=0
  for u in "${UNITES_ON[@]}"; do [ "$(systemctl is-enabled "$u" 2>/dev/null)" = enabled ] || { r=1; [ "$MODE" = verifier ] && dire "non activé : $u"; }; done
  for u in "${MASQUES[@]}"; do [ "$(systemctl is-enabled "$u" 2>/dev/null)" = masked ] || { r=1; [ "$MODE" = verifier ] && dire "non masqué : $u"; }; done
  if [ "$GETTY_TTY1" = couper ] && [ "$(systemctl is-enabled getty@tty1.service 2>/dev/null)" = enabled ]; then
    r=1; [ "$MODE" = verifier ] && dire "getty@tty1 activé : une invite de connexion sur l'écran dès que Plymouth part"
  fi
  return $r
}
p_services() {
  faire "systemctl daemon-reload"
  faire "systemctl enable ${UNITES_ON[*]}"
  faire "systemctl mask ${MASQUES[*]}"
  if [ "$GETTY_TTY1" = couper ] && [ "$(systemctl is-enabled getty@tty1.service 2>/dev/null)" = enabled ]; then
    faire "mkdir -p $ETAT && touch $ETAT/getty-tty1-etait-active && systemctl disable getty@tty1.service"
  fi
}

# La ligne de commande d'un label extlinux : `append` sans `splash`/console=tty/video=, avec nos arguments.
EXTLINUX=/boot/extlinux/extlinux.conf
case "$CMDLINE" in extlinux:*) LABEL=${CMDLINE#extlinux:} ;; *) LABEL=l0 ;; esac
c_cmdline() {
  [ "$CMDLINE" = non ] && return 0
  local cur; cur=$(append_de "$EXTLINUX" "$LABEL"); [ -n "$cur" ] || { [ "$MODE" = verifier ] && dire "pas de label $LABEL dans $EXTLINUX"; return 1; }
  [ "$cur" = "$(voulue "$cur")" ]
}
p_cmdline() {
  local cur new; cur=$(append_de "$EXTLINUX" "$LABEL"); [ -n "$cur" ] || { rouge "pas de label « $LABEL » dans $EXTLINUX"; return 1; }
  new=$(voulue "$cur")
  dire "avant : $cur"; dire "après : $new"
  [ "$MODE" = appliquer ] || return 0
  cp -a "$EXTLINUX" "$EXTLINUX.avant-pxl-bootsplash-$ETIQUETTE"
  awk -v L="$LABEL" -v N="$new" '$1=="label"{l=($2==L)} l && $1=="append"{match($0,/^[ \t]*/); print substr($0,1,RLENGTH) "append " N; next} {print}' \
    "$EXTLINUX" > "$EXTLINUX.pxl-neuf" && mv -f "$EXTLINUX.pxl-neuf" "$EXTLINUX" && printf '  posé  %s (label %s ; copie : %s)\n' "$EXTLINUX" "$LABEL" "$EXTLINUX.avant-pxl-bootsplash-$ETIQUETTE"
}

# ── après le redémarrage : ce que la machine a fait VRAIMENT (lecture seule)
temoins() {
  titre "Après le démarrage — la machine (lecture seule)"
  local c; c=$(cat /proc/cmdline)
  for a in "${CMDLINE_AJOUTER[@]}"; do case " $c " in *" $a "*) ;; *) jaune "/proc/cmdline sans « $a »" ;; esac; done
  for a in $c; do [[ $a =~ $CMDLINE_RETIRER ]] && jaune "/proc/cmdline porte encore « $a »"; done
  dire "modes posés à ce démarrage (dmesg, « Update mode ») :"
  dmesg 2>/dev/null | grep -o 'Update mode to [^,]* for vp[0-9]*' | sed 's/^/    /'
  cat /run/pxl-bootsplash/temoin 2>/dev/null | sed 's/^/    /'   # tty1 et mode du VT au passage de main (doit être 0 ligne)
  journalctl -b -o cat --no-pager -u pxl-bootsplash-mode -u pxl-bootsplash-etapes 2>/dev/null | grep -v '^$' | tail -6 | sed 's/^/    /'
}

# ═══ LE DÉROULÉ ═══════════════════════════════════════════════════════════════════════════════════════════════════════
if [ $RETIRER = 1 ]; then
  titre "Retirer pxl-bootsplash $VERSION"
  faire "systemctl disable ${UNITES_ON[*]} 2>/dev/null; systemctl unmask ${MASQUES[*]}"
  [ -e "$ETAT/getty-tty1-etait-active" ] && faire "systemctl enable getty@tty1.service"
  for f in "$SD/pxl-bootsplash-mode.service" "$SD/pxl-bootsplash-etapes.service" "$SD/pxl-bootsplash-arret.service" \
           "$SD/pxl-bootsplash-fin-arret.service" \
           "$SD"/plymouth-{start,reboot,poweroff,halt,kexec}.service.d/10-pxl-bootsplash.conf \
           ${AFFICHAGE_UNITE:+"$SD/$AFFICHAGE_UNITE.d/20-pxl-bootsplash.conf"}; do [ -e "$f" ] && faire "rm -f '$f'"; done
  [ -e /etc/plymouth/plymouthd.conf.avant-pxl-bootsplash ] && faire "mv -f /etc/plymouth/plymouthd.conf.avant-pxl-bootsplash /etc/plymouth/plymouthd.conf"
  faire "rm -rf $LIB $THEME $ETC $ETAT && systemctl daemon-reload"
  ls "$EXTLINUX".avant-pxl-bootsplash-* >/dev/null 2>&1 && dire "ligne de commande : copies gardées — $(ls "$EXTLINUX".avant-pxl-bootsplash-* | tr '\n' ' ')(à remettre à la main si voulu)"
  exit 0
fi

ETAPES=("1|Paquets (Plymouth, police, libdrm)|c_paquets|p_paquets" "2|Outil de mode (compilé ici)|c_outil|p_outil"
  "3|Thème, moteur, sondes, unités, réglages|c_fichiers|p_fichiers" "4|Images : logo, cartouche, barre (rendues ici)|c_logo|p_logo"
  "5|Services : activés, masques, tty1|c_services|p_services")
[ "$CMDLINE" != non ] && ETAPES+=("6|Ligne de commande (extlinux, label $LABEL)|c_cmdline|p_cmdline")
echo "pxl-bootsplash $VERSION — $MODE${APPAREIL:+ — appareil : $APPAREIL}${AFFICHAGE_UNITE:+ — affichage : $AFFICHAGE_UNITE}"
for e in "${ETAPES[@]}"; do
  IFS='|' read -r n nom c p <<< "$e"; titre "$n. $nom"
  if $c; then ok "fait"; continue; fi
  case "$MODE" in
    verifier) rouge "à faire" ;;
    simulation) $p ;;
    appliquer) if $p && $c; then ok "fait"; else rouge "étape $n incomplète"; fi ;;
  esac
done
if [ "$CMDLINE" = non ] && [ "$MODE" = verifier ]; then
  titre "Ligne de commande (gérée par l'appareil)"
  cur=$(append_de "$EXTLINUX" l0); [ -n "$cur" ] && { [ "$cur" = "$(voulue "$cur")" ] && ok "label l0 conforme" || jaune "label l0 : attendu « $(voulue "$cur") »"; }
fi
[ "$MODE" = verifier ] && temoins
titre "Bilan"
case "$MODE" in
  simulation) dire "SIMULATION : rien n'a été touché. Relancer avec --appliquer." ;;
  verifier)   [ $ROUGES = 0 ] && ok "tout est vert ($JAUNES avertissement(s))" || rouge "$ROUGES point(s) rouge(s)" ;;
  appliquer)  [ $ROUGES = 0 ] && ok "posé ($JAUNES avertissement(s)) — visible au PROCHAIN démarrage, rien n'a été relancé" || rouge "$ROUGES rouge(s)" ;;
esac
[ $ROUGES = 0 ]

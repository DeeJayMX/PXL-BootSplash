#!/bin/bash
# test/tests.sh — ce qui se prouve SANS l'appareil. Ce qui ne se prouve qu'au démarrage (le mode réellement posé,
# l'absence de noir au passage de main) se MESURE sur l'appareil : `installer.sh --verifier` après redémarrage, et la
# vidéo de l'écran. ⚠️ Chaque contrôle ci-dessous a été vu ÉCHOUER une fois (sabotage), sinon il ne prouve rien.
#   bash test/tests.sh
set -u
ICI=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ECHECS=0
bon()  { printf '  ✅ %s\n' "$*"; }
faux() { printf '  🔴 %s\n' "$*"; ECHECS=$((ECHECS + 1)); }

echo "1 · syntaxe des scripts"
for f in "$ICI"/installer.sh "$ICI"/lib/*.sh "$ICI"/lib/sondes/*.sh; do bash -n "$f" || faux "syntaxe : $f"; done
bon "bash -n"

echo "2 · le repli calculé = le mode que le noyau fabriquait pour video=HDMI-A-1:800x480@60 (pxl-tx, modetest, 30/10)"
# ⚠️ UN seul mode de référence mesuré : il voit la synchro, les porches, l'horloge et les polarités (sabotages du 30/10
# : V_SYNC_RQD, NHSYNC), PAS les paramètres C et M du GTF — à 800x480 la division entière les absorbe (C=82 ou M=601
# rendent le même mode). Un second mode de référence se relève avec un autre `video=` sur un appareil de labo.
if gcc -O2 -Wall -Werror -o "$T/mode" "$ICI/src/pxl-bootsplash-mode.c" $(pkg-config --cflags --libs libdrm 2>/dev/null) 2>"$T/cc"; then
  r=$("$T/mode" --gtf 800x480@60)
  [ "$r" = "800 816 896 992 480 481 484 497 29605 -hsync +vsync" ] && bon "GTF 800x480@60 : $r" || faux "GTF 800x480@60 : « $r »"
else faux "compilation : $(head -3 "$T/cc")"; fi

echo "3 · la ligne de commande voulue, sur la VRAIE ligne de pxl-tx (30/10)"
. "$ICI/lib/cmdline.sh"
AVANT="root=UUID=2e6a37fe-c35a-4fa1-b3e6-932217ec4dcb console=ttyFIQ0,1500000n8 quiet splash loglevel=4 rw video=HDMI-A-1:800x480@60 video=HDMI-A-2:1920x1080@60 earlycon consoleblank=0 console=tty1 coherent_pool=2M irqchip.gicv3_pseudo_nmi=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1 snd_usb_audio.lowlatency=0"
ATTENDU="root=UUID=2e6a37fe-c35a-4fa1-b3e6-932217ec4dcb console=ttyFIQ0,1500000n8 quiet loglevel=4 rw earlycon consoleblank=0 coherent_pool=2M irqchip.gicv3_pseudo_nmi=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1 snd_usb_audio.lowlatency=0 nosplash rhgb plymouth.graphical plymouth.ignore-serial-consoles plymouth.nolog logo.nologo vt.global_cursor_default=0 systemd.show_status=false"
r=$(voulue "$AVANT")
[ "$r" = "$ATTENDU" ] && bon "splash, console=tty1 et les deux video= retirés ; console série gardée ; ajouts en fin" || faux "voulue : « $r »"
[ "$(voulue "$r")" = "$r" ] && bon "idempotente (relancer ne change rien)" || faux "voulue n'est pas idempotente"
printf 'label l0\n\tlinux /boot/v\n\tappend %s\n\nlabel l0r\n\tappend autre\n' "$AVANT" > "$T/ext"
[ "$(append_de "$T/ext" l0)" = "$AVANT" ] && [ "$(append_de "$T/ext" l0r)" = autre ] && bon "append_de lit le bon label" || faux "append_de"

echo "4 · le moteur d'étapes, contre un faux Plymouth"
mkdir -p "$T/bin" "$T/lib/sondes" "$T/run"
# le faux plymouth : journalise, répond au ping tant que $T/vivant existe
cat > "$T/bin/plymouth" <<EOF
#!/bin/bash
echo "\$*" >> "$T/plymouth.log"
case "\$1" in --ping) [ -e "$T/vivant" ] ;; quit) rm -f "$T/vivant" ;; esac
EOF
printf '#!/bin/bash\nexit 0\n' > "$T/bin/systemctl"   # « tout est actif »
chmod +x "$T/bin/plymouth" "$T/bin/systemctl"
printf 'LIBELLE="Un"\nsonde() { echo "2|ok à $1 s"; }\n' > "$T/lib/sondes/un.sh"
printf 'LIBELLE="Deux"\nsonde() { echo "1|en cours"; }\n' > "$T/lib/sondes/deux.sh"
printf 'ETAPES="un absente deux"\nPRODUIT="Banc"\nAFFICHAGE_UNITE=banc.service\nAFFICHAGE_ETAPE=deux\nFIN_S=600\nDUREE_MAX=999999\n' > "$T/appareil.conf"
touch "$T/vivant"
( sleep 1.5; touch "$T/run/lache"; sleep 1; touch "$T/run/signal/premiere-image" ) &
PATH="$T/bin:$PATH" PXL_BOOTSPLASH_CONF="$T/appareil.conf" PXL_BOOTSPLASH_LIB="$T/lib" PXL_BOOTSPLASH_RUN="$T/run" \
  timeout 20 bash "$ICI/lib/etapes.sh" > "$T/etapes.out" 2>&1
rc=$?; wait
L=$(cat "$T/plymouth.log" 2>/dev/null)
grep -q 'update --status=pxl|1|n|Un' <<< "$L" && grep -q 'update --status=pxl|2|n|Deux' <<< "$L" \
  && bon "libellés envoyés, numérotés sans trou (la sonde absente est sautée)" || faux "libellés : $(grep -c n\| <<< "$L")"
grep -q 'pxl|1|2|ok à' <<< "$L" && grep -q 'pxl|2|1|en cours' <<< "$L" && bon "états des sondes envoyés" || faux "états"
[ "$(grep -c 'pxl|2|1|en cours' <<< "$L")" = 1 ] && bon "un état inchangé n'est envoyé qu'une fois" || faux "état renvoyé à chaque tour"
grep -q 'update --status=pxl|F|0|.*Banc' <<< "$L" && bon "pied de page" || faux "pied de page"
[ "$(cat "$T/run/etape-affichage" 2>/dev/null)" = 2 ] && bon "l'étape d'affichage est la 2ᵉ (ce que lit le lâcher)" || faux "etape-affichage"
grep -qx 'quit --retain-splash' <<< "$L" && grep -q 'première image' "$T/etapes.out" && bon "Plymouth part sur le SIGNAL de première image, en --retain-splash (sinon il repose le mode préféré d'une prise : pxl-tx, 30/10)" || faux "fin : $(tail -2 "$T/etapes.out")"
[ $rc = 0 ] && bon "le moteur s'arrête avec Plymouth (rc 0)" || faux "le moteur n'est pas sorti (rc $rc)"

echo "5 · sans signal, il ne part PAS avant son plafond (deux secondes ici)"
rm -f "$T/plymouth.log" "$T/run/lache" "$T/run/signal/premiere-image"; touch "$T/vivant"
printf 'ETAPES="un"\nAFFICHAGE_UNITE=banc.service\nFIN_S=2\nDUREE_MAX=999999\n' > "$T/appareil2.conf"
( sleep 0.5; touch "$T/run/lache" ) &
d0=$(date +%s.%N)
PATH="$T/bin:$PATH" PXL_BOOTSPLASH_CONF="$T/appareil2.conf" PXL_BOOTSPLASH_LIB="$T/lib" PXL_BOOTSPLASH_RUN="$T/run" \
  timeout 20 bash "$ICI/lib/etapes.sh" > "$T/etapes2.out" 2>&1
wait; d=$(echo "$(date +%s.%N) - $d0" | bc)
grep -q 'aucun signal' "$T/etapes2.out" && [ "$(echo "$d >= 2" | bc)" = 1 ] && bon "parti au plafond, après ${d%.*} s, et il le DIT" || faux "plafond : $d s — $(tail -1 "$T/etapes2.out")"

echo "6 · la rivière se régénère À L'IDENTIQUE (graine fixe) et se reboucle (deux périodes égales)"
python3 -I "$ICI/outils/riviere.py" | cmp -s - "$ICI/theme/riviere.svg" && bon "theme/riviere.svg = outils/riviere.py" || faux "riviere.svg ≠ sa génération"
python3 -I - "$ICI/theme/riviere.svg" <<'PY' && bon "seconde période = première (bouclage net)" || faux "la rivière ne se reboucle pas"
import re, sys
r = re.findall(r'<rect x="(\d+)" y="(\d+)" width="5" height="5" fill="(#[0-9a-f]+)"/>', open(sys.argv[1]).read())
a = {(int(x), int(y), c) for x, y, c in r if int(x) < 1100}; b = {(int(x) - 1100, int(y), c) for x, y, c in r if int(x) >= 1100}
sys.exit(0 if a and a == b else 1)
PY

echo "7 · le script Plymouth : accolades et parenthèses équilibrées (pas de Plymouth ici pour l'exécuter)"
for c in '{}' '()' '[]'; do
  o=$(tr -cd "${c:0:1}" < "$ICI/theme/pxl.script" | wc -c); f=$(tr -cd "${c:1:1}" < "$ICI/theme/pxl.script" | wc -c)
  [ "$o" = "$f" ] && bon "$c : $o ouvrants, $f fermants" || faux "$c : $o ouvrants, $f fermants"
done

echo
[ $ECHECS = 0 ] && echo "✅ tout est vert" || echo "🔴 $ECHECS échec(s)"
[ $ECHECS = 0 ]

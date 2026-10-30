#!/bin/bash
# pxl-bootsplash-fin-arret — LA DERNIÈRE MARCHE de l'arrêt (pxl-bootsplash-fin-arret.service, 1.1.3, 30/10).
# Eliott : « à l'extinction la barre ne va pas au bout, ça s'éteint avant ». Tous les services sont arrêtés (l'unité
# passe après shutdown.target et umount.target, juste avant systemd-reboot/-poweroff) : la barre va à 100 %, l'étape
# « Carte » au vert, et on TIENT FIN_ARRET_S secondes (1 par défaut, appareil.conf) pour qu'on la voie pleine.
# Ne retient jamais plus de 5 s, et sort toujours en 0.
CONF=${PXL_BOOTSPLASH_CONF:-/etc/pxl-bootsplash/appareil.conf}
FIN_ARRET_S=1
# shellcheck disable=SC1090
. "$CONF" 2>/dev/null
plymouth --ping 2>/dev/null || exit 0
plymouth update --status="pxl|B|Z|" 2>/dev/null
# l'étape « Carte » est la dernière des étapes d'arrêt : son numéro est celui du dernier libellé envoyé
e=$(cat /run/pxl-bootsplash/etape-carte 2>/dev/null)
if [ -n "$e" ]; then
  if systemctl list-jobs --no-legend 2>/dev/null | grep -q 'reboot\.target\|kexec\.target'; then m="redémarrage de la carte"
  else m="coupure de l'alimentation"; fi
  plymouth update --status="pxl|$e|2|$m" 2>/dev/null
fi
s=$FIN_ARRET_S; [ "${s%%.*}" -gt 5 ] 2>/dev/null && s=5
sleep "$s"
exit 0

# Sonde commune d'ARRÊT « Carte » — la dernière marche : plus aucun service, le noyau va redémarrer ou couper.
LIBELLE="Carte"
sonde() {
  if [ "$(systemctl list-jobs --no-legend 2>/dev/null | awk '$3=="stop"' | wc -l)" = 0 ]; then
    if systemctl list-jobs --no-legend 2>/dev/null | grep -q 'reboot\.target'; then echo "1|redémarrage…"; else echo "1|coupure…"; fi
  else echo "0|"; fi
}

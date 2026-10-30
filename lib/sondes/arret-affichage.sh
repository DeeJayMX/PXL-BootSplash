# Sonde commune d'ARRÊT « Affichage » — le programme d'affichage de l'appareil (AFFICHAGE_UNITE) est-il arrêté ?
LIBELLE="Affichage"
sonde() {
  [ -n "${AFFICHAGE_UNITE:-}" ] || { echo "2|"; return; }
  if systemctl is-active -q "$AFFICHAGE_UNITE"; then echo "1|arrêt de ${AFFICHAGE_UNITE%.service}…"
  else echo "2|${AFFICHAGE_UNITE%.service} arrêté"; fi
}

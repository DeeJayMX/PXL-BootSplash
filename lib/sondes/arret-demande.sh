# Sonde commune d'ARRÊT « Redémarrage » / « Extinction » — ce que systemd est en train de faire (son travail en cours).
if systemctl list-jobs --no-legend 2>/dev/null | grep -q 'reboot\.target\|kexec\.target'; then LIBELLE="Redémarrage"
else LIBELLE="Extinction"; fi
DEMANDE_A=$(date +%Hh%M:%S)
sonde() { echo "2|demandé à $DEMANDE_A"; }

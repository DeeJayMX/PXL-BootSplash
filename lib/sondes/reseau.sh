# Sonde commune « Réseau » — l'adresse que le DHCP a donnée. Réglages (appareil.conf) :
#   RESEAU_IFACES="enP4p65s0 wlan0"  les interfaces, par ordre de préférence (défaut : eth0 end0 wlan0)
#   RESEAU_SECOURS=192.168.55.10      une adresse FIXE de secours, qui ne prouve aucun DHCP (elle ne compte pas)
LIBELLE="Réseau"
sonde() {
  local i a
  for i in ${RESEAU_IFACES:-eth0 end0 wlan0}; do
    a=$(ip -4 -o addr show dev "$i" scope global 2>/dev/null | awk '{sub(/\/.*/, "", $4); print $4}' \
        | grep -vx "${RESEAU_SECOURS:-x}" | head -1)
    [ -n "$a" ] && { case "$i" in wl*) echo "2|Wi-Fi · $a" ;; *) echo "2|Ethernet · $a" ;; esac; return; }
  done
  i=$(set -- ${RESEAU_IFACES:-eth0 end0 wlan0}; echo "$1")
  if [ -n "${RESEAU_SECOURS:-}" ] && ip -4 -o addr show dev "$i" 2>/dev/null | grep -q " $RESEAU_SECOURS/"; then
    echo "4|aucun DHCP — adresse de secours $RESEAU_SECOURS"
  elif [ "$(cat "/sys/class/net/$i/carrier" 2>/dev/null)" = 1 ]; then echo "1|câble branché, attente d'une adresse…"
  else echo "1|câble Ethernet débranché"; fi
}

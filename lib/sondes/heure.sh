# Sonde commune « Heure » — chrony (sinon systemd-timesyncd). Une carte sans pile n'a pas d'heure avant la synchro :
# tout ce qui attend `time-sync.target` attend CETTE étape.
LIBELLE="Heure"
sonde() {
  local src
  if command -v chronyc >/dev/null; then
    if chronyc -n tracking 2>/dev/null | grep -q '^Leap status *: Normal'; then
      src=$(timeout 2 chronyc tracking 2>/dev/null | sed -n 's/^Reference ID *: [0-9A-F]* (\(.*\))$/\1/p')
      echo "2|synchronisée${src:+ sur $src} — $(date +%H:%M:%S)"; return
    fi
  elif [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ]; then
    echo "2|synchronisée — $(date +%H:%M:%S)"; return
  fi
  if [ "$1" -gt 90 ]; then echo "4|aucun serveur de temps — heure NON fiable"; else echo "1|synchronisation…"; fi
}

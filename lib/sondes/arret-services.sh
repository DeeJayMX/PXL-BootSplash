# Sonde commune d'ARRÊT « Services » — combien restent à arrêter, et CELUI qui retient l'arrêt, depuis combien de temps.
# (Le cas qui l'a fait écrire : pxl-genlock-audio@desk a retenu l'arrêt de pxl-tx 7 min 50 le 30/10 — à l'écran, on le
# voyait sous forme de « Job … stop running (5min 29s / 15min) » dans le journal ; ici on le dit en clair.)
LIBELLE="Services"
sonde() {
  local n u t0 now d
  n=$(systemctl list-jobs --no-legend 2>/dev/null | awk '$3=="stop" && $4=="running"' | wc -l)
  if [ "$n" = 0 ]; then echo "2|tous arrêtés"; return; fi
  u=$(systemctl list-jobs --no-legend 2>/dev/null | awk '$3=="stop" && $4=="running" {print $2}' | while read -r x; do
        printf '%s %s\n' "$(systemctl show -p StateChangeTimestampMonotonic --value "$x" 2>/dev/null)" "$x"; done \
      | sort -n | head -1)
  t0=${u%% *}; u=${u#* }; now=$(awk '{printf "%d", $1 * 1000000}' /proc/uptime)
  d=$(( (now - ${t0:-$now}) / 1000000 ))
  if [ "$d" -ge 5 ]; then echo "1|$n en cours d'arrêt — attend ${u%.service} depuis ${d} s"
  else echo "1|$n en cours d'arrêt"; fi
}

# Sonde commune « PXLnet » — le réseau privé PXL (Tailscale). Le SERVICE garde son nom ; seul l'affiché est PXLnet
# (décision d'Eliott pour la box, 04/10/2026 : « pas de mention de Tailscale dans les interfaces »).
LIBELLE="PXLnet"
sonde() {
  local a
  a=$(tailscale ip -4 2>/dev/null | head -1)
  if [ -n "$a" ] && tailscale status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; then echo "2|$a"
  elif systemctl is-active -q tailscaled; then echo "1|connexion…"
  else echo "0|"; fi
}

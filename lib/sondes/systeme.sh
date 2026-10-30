# Sonde commune « Système » — la cible de démarrage. Les noms d'unités que systemd envoie à Plymouth s'affichent en
# détail tant qu'elle n'est pas faite (pxl.script).
LIBELLE="Système"
sonde() {
  if systemctl is-active -q multi-user.target; then echo "2|démarré en $1 s"
  elif systemctl is-active -q basic.target; then echo "1|services en cours de lancement"; fi
}

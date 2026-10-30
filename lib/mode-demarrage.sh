#!/bin/bash
# Lance pxl-bootsplash-mode avec les réglages de l'appareil (pxl-bootsplash-mode.service).
CONF=${PXL_BOOTSPLASH_CONF:-/etc/pxl-bootsplash/appareil.conf}
CONNECTEUR=""; SANS_EDID=800x480@60
# shellcheck disable=SC1090
. "$CONF" 2>/dev/null
exec /usr/lib/pxl-bootsplash/mode ${CONNECTEUR:+--connecteur "$CONNECTEUR"} --sans-edid "$SANS_EDID" --attente 10

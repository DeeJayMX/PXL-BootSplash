# CLAUDE.md — pxl-bootsplash

L'écran de démarrage COMMUN aux appareils PXL (voir `README.md`). Un appareil n'apporte que `appareil.conf` et ses
sondes ; rien de propre à un appareil n'entre ici.

## Règles (celles des autres dépôts PXL)

- 🕐 Heure française partout. Prose et commentaires en français.
- **Chaque fait porte sa provenance** : mesuré (sur quel appareil, quelle date), lu (quel fichier, de quel objet), déduit.
  Un fait lu sur un autre appareil ou une autre puce se marque comme tel.
- **Une divergence s'AJOUTE, datée, avec son mécanisme** ; on ne réécrit pas un fait faux, on le corrige par un erratum.
- **Jamais de binaire versionné** : l'outil de mode se compile sur l'appareil, le logo s'y rend (Chromium/rsvg).
- **Un écran de démarrage ne retient JAMAIS le démarrage** : tout sort en 0, le complément du programme d'affichage est
  en `-+` (un échec ne l'empêche pas de démarrer).
- 🔴 **Rien n'ouvre `/dev/dri/card0` pendant le passage de main** (le premier qui ouvre devient maître DRM).
- **Un contrôle se voit échouer** : tout test neuf est saboté une fois (`bash test/tests.sh`).
- `VERSION` (MAJEUR.MINEUR.CORRECTIF) se relève dans le commit qui change le comportement.
- Sur un appareil EN SERVICE (pxl-tx2, mur LED) : rien sans l'heure choisie par Eliott. Un redémarrage s'annonce avec
  une heure et se fait à cette heure.

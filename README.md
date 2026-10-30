# pxl-bootsplash — l'écran de démarrage des appareils PXL

Du mode posé par le noyau jusqu'à la première image du programme d'affichage de l'appareil : **le logo PXL, puis les
étapes du démarrage lues dans l'état réel de la machine**, le nom et les versions en pied de page. Sans texte, sans
curseur, et **sans changement de mode** quand l'écran annonce le sien.

Né le 30/10/2026 (demande d'Eliott) pour le mur LED de pxl-tx2 (PXL Switch) : à chaque coupure de courant le mur
montrait ~20 s de console Linux en 800x480, puis changeait de mode deux fois. Le style est celui de la box PXL GFX
(`DeeJayMX/PXL-Kiosk-RK3566`, thème Plymouth du 02/10/2026) ; ce dépôt le rend **commun à tous les appareils** : ce
qui est propre à un appareil tient dans **un fichier de réglages et quelques sondes**.

## Ce qu'il fait, dans l'ordre du démarrage

| moment | qui | quoi |
|---|---|---|
| noyau | ligne de commande | plus de `video=` : le noyau prend lui-même le **mode préféré de l'EDID** ; plus de `console=tty*` ni de `splash` : rien n'écrit sur l'écran |
| DRM prêt | `pxl-bootsplash-mode` | vérifie ce mode ; **sans EDID** (après re-sonde), pose le repli `SANS_EDID` (800x480@60 par défaut) — calculé en **GTF comme `video=`**, au timing près |
| juste après | Plymouth, thème `pxl` | reprend le **mode actif** (renderer `drm`), logo + étapes |
| tout le démarrage | `pxl-bootsplash-etapes` | relit chaque étape toutes les 0,5 s (sondes) et l'envoie à Plymouth |
| avant le programme d'affichage | `pxl-bootsplash-lacher` | Plymouth **lâche** le DRM sans partir : son image reste balayée |
| première image du programme | le programme crée `$PXL_BOOTSPLASH_TEMOIN` | Plymouth part — son tampon n'est plus balayé, le retirer ne coupe rien |

## Poser sur un appareil

```bash
sudo ./installer.sh --appareil /chemin/appareil.conf --sondes /chemin/sondes            # simulation
sudo ./installer.sh --appareil … --sondes … [--cmdline extlinux:l0] --appliquer          # pose
sudo ./installer.sh --verifier                                                           # contrôle (lecture seule)
sudo ./installer.sh --retirer --appliquer                                                # défait
```

Il ne redémarre rien, ne touche ni à l'initrd ni à U-Boot, et garde une copie `*.avant-pxl-bootsplash` de tout ce
qu'il remplace. `--cmdline non` (défaut) : l'appareil gère sa ligne de commande (PXL Switch : `installer-carte.sh`) ;
`--verifier` la contrôle quand même.

**Ce qu'un appareil fournit** — voir `exemples/appareil.conf` :
- `ETAPES` : la liste des sondes (8 au plus). Communes : `systeme`, `reseau`, `heure`, `pxlnet`. Les siennes, dans
  `--sondes` : un fichier `<nom>.sh` qui définit `LIBELLE="…"` et `sonde() { echo "ÉTAT|détail"; }` (0 attente ·
  1 en cours · 2 fait · 3 défaut · 4 avertissement ; `$1` = secondes depuis le démarrage). **Une sonde lit l'état
  réel**, jamais un délai.
- `AFFICHAGE_UNITE` : l'unité systemd qui prend l'écran. L'installeur lui pose un complément ; **le programme doit
  créer le fichier `$PXL_BOOTSPLASH_TEMOIN` quand sa première image est balayée** (une ligne de code). Sans ce
  signal, Plymouth part au bout de `FIN_S` secondes, et ce cas peut noircir l'écran un instant.
- `SANS_EDID`, `CONNECTEUR`, `pied()`, `GETTY_TTY1`.

## Les pièges, mesurés — ne pas les repayer

- **`video=` passe avant le mode préféré de l'EDID** (lu dans `drm_client_modeset`) : il imposait 800x480 au mur qui
  annonce 1536x768. Le noyau ne sait pas dire « sinon » : c'est `pxl-bootsplash-mode` qui le dit.
- **« connected » ne veut pas dire « caractérisé »** (PXL-Switcher, 09/08) : au démarrage un connecteur peut se dire
  branché avec la liste de repli du pilote. L'outil **re-sonde** avant de conclure « pas d'EDID ».
- **Un processus qui part retire ses tampons, et retirer le tampon balayé éteint l'écran** (box, `pxl-mode.c`,
  02/10). D'où : l'outil de mode GARDE son tampon jusqu'à ce que Plymouth le remplace, et Plymouth ne part qu'après
  la première image du programme.
- 🔴 **Ne jamais ouvrir `/dev/dri/card0` pendant le passage de main** : entre `deactivate` et l'ouverture par le
  programme, il n'y a aucun maître ; le premier qui ouvre le devient, et un programme non root ne pourrait plus le
  prendre. D'où un signal par fichier, pas une sonde DRM.
- **Une ligne de journal ne prouve pas une image à l'écran** : sur pxl-tx (30/10) le compositeur écrivait
  « présentation DIRECTE » à 16,99 s et le CRTC n'est repassé en 1920x1080 qu'à 21,35 s.
  🔴 **ERRATUM du même jour (18h20) : cet exemple est FAUX.** Les deux heures viennent de DEUX horloges : le journal
  date les programmes sur l'horloge monotone, `dmesg` (et les lignes `kernel:` du journal) sur celle du noyau, qui a
  **4,05 s d'avance** sur pxl-tx (mesuré : une marque écrite dans `/dev/kmsg` à 51,36 s monotone porte 55,39 s). Le
  vrai écart était ~0,3 s. ⚠️ **Ne jamais comparer une heure de `dmesg` à une heure de programme du journal.** Le
  signal par fichier reste le bon choix, pour la raison du point précédent (le maître DRM), pas pour celle-ci.
- **`splash` réveille le Plymouth de l'initrd**, qui n'a pas de DRM à ce moment-là (Rock 5B : pilote prêt à ~5,7 s,
  après le passage à la racine). Celui du système suffit — **l'initrd n'est pas touché** (il porte le r8125 avec PTP
  sur PXL Switch).
- 🔴 **ERRATUM 1.0.3 (30/10, mesuré sur pxl-tx)** : sans `splash`, le Plymouth de Debian 22.02 affiche le JOURNAL
  (thème « details ») — il lui faut `splash` ou `rhgb` ; et le script de l'initrd de Debian démarre Plymouth PAR
  DÉFAUT, avec le thème de l'initrd. D'où `nosplash rhgb` sur la ligne et les conditions de `plymouth-start` reposées
  sans `!nosplash`. La phrase précédente (« pas de DRM dans l'initrd ») est fausse elle aussi : 5,7 s était une heure
  `dmesg` ; le mode du noyau est posé vers 1,9 s.
- Plymouth en mode TEXTE avec une console série (« details forced ») : `plymouth.ignore-serial-consoles`, et
  `plymouth.graphical` puisque `splash` n'est plus là (box, 02/10).

- 🔴 **1.1.5 (30/10, mesuré sur pxl-tx à 19h28:27) — le chien de garde a pris un programme qui DÉMARRE pour un
  programme arrêté** : deux lectures systemd séparées (`is-active` puis `show ActiveState`) encadraient « Started » ⇒
  fausse alarme 26 ms après le départ ⇒ `plymouth reactivate` sous le compositeur ⇒ bataille de modes sur la 2ᵉ sortie
  (4K60 préféré de l'écran contre le 1080p60 demandé), genlock perdu. Désormais : UNE lecture d'`ActiveState` par essai,
  seuls `inactive`/`failed` comptent, confirmés deux fois à 0,5 s. Test 6 (vu échouer sur l'ancien code).

## Ce qui reste à mesurer sur chaque appareil

Le passage de main sans noir (`FIN=deactivate`, déduit) contre `quit --retain-splash` (la box) — témoins : les lignes
`Update mode` de `dmesg` (`installer.sh --verifier` les liste) et **une vidéo de l'écran**, de la mise sous tension à la
première image. Et ce qu'affiche le chargeur (U-Boot) avant Linux : hors de ce dépôt, on n'y touche pas.

## Tests

```bash
bash test/tests.sh     # syntaxe · GTF = mode du noyau · ligne de commande · moteur contre un faux Plymouth
```
Chaque contrôle a été vu échouer une fois (sabotage). Limite écrite dans le test : un seul mode GTF de référence.

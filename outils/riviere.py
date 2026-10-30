#!/usr/bin/env python3
# outils/riviere.py — génère theme/riviere.svg, la texture de la barre de chargement : une « rivière de QR code »,
# des modules carrés en pixels francs (crispEdges), sur 6 rangées, qui se REBOUCLE sur sa période (la barre la fait
# défiler en continu : Image.Crop à un décalage qui tourne). Déterministe (graine fixe) : relancer rend le même fichier.
#   python3 -I outils/riviere.py > theme/riviere.svg
import random
MODULE, RANGEES, PERIODE = 5, 6, 220          # 5 px × 6 rangées = 30 px de haut ; 220 colonnes = 1100 px = la piste
r = random.Random(20261030)
COULEURS = ["#3dc7eb", "#3dc7eb", "#3dc7eb", "#7fdcf2", "#eef2f6", "#2a8fb0"]   # cyan « en cours », plus clair, blanc, sombre
# des colonnes à densité variable : une rivière a des courants — des passages pleins, d'autres clairsemés, comme un QR
grille = []
densite = 0.5
for c in range(PERIODE):
    densite = min(0.85, max(0.25, densite + r.uniform(-0.12, 0.12)))
    grille.append([r.random() < densite for _ in range(RANGEES)])
# de temps en temps un « œil » de QR (carré plein 3x3 entouré de vide), pour que la texture se lise comme un code
for c0 in range(6, PERIODE - 6, 37):
    l0 = r.randint(0, RANGEES - 3)
    for c in range(c0 - 1, c0 + 4):
        for l in range(max(0, l0 - 1), min(RANGEES, l0 + 4)):
            grille[c][l] = (c0 <= c < c0 + 3) and (l0 <= l < l0 + 3)
# la couleur de chaque module, tirée UNE fois : la seconde période est la copie exacte de la première (bouclage net)
couleur = [[r.choice(COULEURS) if plein else None for plein in col] for col in grille]
largeur = 2 * PERIODE * MODULE                 # deux périodes : un recadrage à n'importe quel décalage < période tient
print(f'<svg xmlns="http://www.w3.org/2000/svg" width="{largeur}" height="{RANGEES * MODULE}" '
      f'viewBox="0 0 {largeur} {RANGEES * MODULE}" shape-rendering="crispEdges">')
print('<!-- pxl-bootsplash : rivière de QR code (outils/riviere.py, graine 20261030) — ne pas éditer à la main -->')
for rep in (0, 1):
    for c, col in enumerate(couleur):
        for l, coul in enumerate(col):
            if coul:
                print(f'<rect x="{(rep * PERIODE + c) * MODULE}" y="{l * MODULE}" width="{MODULE}" height="{MODULE}" fill="{coul}"/>')
print('</svg>')

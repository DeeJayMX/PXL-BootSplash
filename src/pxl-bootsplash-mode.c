// pxl-bootsplash-mode — LE MODE DE L'ÉCRAN AU DÉMARRAGE : celui que l'écran préfère (EDID), sinon un mode de repli.
//
// 30/10/2026, décision d'Eliott : « le mode préféré annoncé par l'écran, sinon 800x480 ». Le noyau ne sait pas dire
// « sinon » : `video=` passe AVANT le mode préféré (drm_client_modeset, lu), donc il imposait 800x480 au mur LED de
// pxl-tx2 qui annonce 1536x768 — une resynchro du NovaStar à chaque démarrage. La décision descend donc ici :
//   · la ligne de commande ne porte plus de `video=` : le noyau prend lui-même le mode préféré quand il y a un EDID ;
//   · ce programme, lancé avant Plymouth, VÉRIFIE ce mode, et ne pose le repli que s'il n'y a VRAIMENT pas d'EDID.
//
// 🔴 « connected » ne veut pas dire « caractérisé » (PXL-Switcher, pxl-connecteurs.sh, mesuré le 09/08/2026) : au
// démarrage un connecteur peut se dire branché avec la liste de REPLI du pilote, l'EDID n'étant pas encore lisible.
// Conclure « pas d'EDID » sur la première lecture enverrait un écran capable de 1536x768 en 800x480. Avant de conclure,
// on re-sonde (`detect` dans /sys/class/drm/…/status, comme pxl-connecteurs.sh) jusqu'à --sondes fois.
//
// ⭐ Le repli est calculé comme le NOYAU calcule `video=LxH@R` sans « M » : en GTF (drm_gtf_mode, paramètres par
// défaut). Le 800x480@60 qu'on calcule est donc AU TIMING PRÈS celui que les écrans 7" recevaient avec l'ancien
// `video=HDMI-A-1:800x480@60` — vérifié par le test contre le mode relevé sur pxl-tx (30/10, modetest) :
// `800 816 896 992 / 480 481 484 497`, 29 605 kHz, -hsync +vsync.
//
// ⚠️ POSER UN MODE OBLIGE À GARDER SON TAMPON (PXL-Kiosk-RK3566, pxl-mode.c, mesuré le 02/10/2026) : un processus qui
// se termine retire ses tampons, et retirer le tampon balayé ÉTEINT l'écran. Après avoir posé, on rend le DRM master
// (drmDropMaster : Plymouth, qui ouvre ensuite, le prend) et un fils GARDE le tampon jusqu'à ce que quelqu'un d'autre
// balaie ce CRTC (Plymouth), ou --tenir secondes au plus. Le père sort tout de suite (systemd : Type=forking).
// Quand le mode est déjà le bon — le cas d'un écran à EDID —, on ne touche à RIEN : ni master, ni tampon.
//
//   pxl-bootsplash-mode [--connecteur HDMI-A-1] [--sans-edid 800x480@60|aucun] [--sondes 3] [--attente 15] [--tenir 120]
//   pxl-bootsplash-mode --etat [...]          dit ce qu'il ferait, ne touche rien (lecture seule)
//   pxl-bootsplash-mode --gtf 800x480@60      imprime le mode GTF calculé (test)
//   pxl-bootsplash-mode --fb [--connecteur X] imprime « CRTC TAMPON LxH@R » de ce qui est balayé (lecture seule)
// ⭐ --fb est LE témoin de « l'affichage a pris l'écran » (pxl-bootsplash-etapes) : une ligne de journal ne le prouve
//   pas — mesuré sur pxl-tx le 30/10, le compositeur écrit « présentation DIRECTE » à 16,99 s et le CRTC n'est
//   repassé en 1920x1080 qu'à 21,35 s. Le tampon balayé, lui, est l'état du noyau.
// Sortie : 0 toujours (un écran de démarrage ne doit jamais retenir le démarrage) — sauf --gtf illisible (2).
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

static int g_etat = 0;   // --etat : lecture seule
#define dire(...) do { printf("pxl-bootsplash-mode : " __VA_ARGS__); printf("\n"); fflush(stdout); } while (0)

// ─── Le GTF du noyau (drm_gtf_mode → drm_gtf_mode_complex, M=600 2C=80 K=128 2J=40), progressif, sans marges ───
// Recopié du noyau pour donner le MÊME mode que `video=LxH@R` : même arithmétique entière, mêmes arrondis.
static int gtf(int hdisplay, int vdisplay, int vrefresh, drmModeModeInfo *m) {
  if (hdisplay <= 0 || vdisplay <= 0 || vrefresh <= 0) return -1;
  const unsigned GTF_CELL_GRAN = 8, GTF_MIN_V_PORCH = 1, V_SYNC_RQD = 3, H_SYNC_PERCENT = 8, MIN_VSYNC_PLUS_BP = 550;
  const unsigned GTF_M = 600, GTF_2C = 80, GTF_K = 128, GTF_2J = 40;
  const unsigned GTF_C_PRIME = ((((GTF_2C - GTF_2J) * GTF_K / 256) + GTF_2J) / 2);
  const unsigned GTF_M_PRIME = (GTF_K * GTF_M / 256);
  unsigned hdisplay_rnd = (hdisplay + GTF_CELL_GRAN / 2) / GTF_CELL_GRAN * GTF_CELL_GRAN;
  unsigned vdisplay_rnd = vdisplay, vfieldrate_rqd = vrefresh;
  unsigned tmp1 = (1000000 - MIN_VSYNC_PLUS_BP * vfieldrate_rqd) / 500;
  unsigned tmp2 = (vdisplay_rnd + GTF_MIN_V_PORCH) * 2;
  unsigned hfreq_est = (tmp2 * 1000 * vfieldrate_rqd) / tmp1;
  int vsync_plus_bp = MIN_VSYNC_PLUS_BP * hfreq_est / 1000;
  vsync_plus_bp = (vsync_plus_bp + 500) / 1000;
  unsigned vtotal_lines = vdisplay_rnd + vsync_plus_bp + GTF_MIN_V_PORCH;
  unsigned total_active_pixels = hdisplay_rnd;
  unsigned ideal_duty_cycle = GTF_C_PRIME * 1000 - (GTF_M_PRIME * 1000000 / hfreq_est);
  unsigned hblank = total_active_pixels * ideal_duty_cycle / (100000 - ideal_duty_cycle);
  hblank = (hblank + GTF_CELL_GRAN) / (2 * GTF_CELL_GRAN);
  hblank = hblank * 2 * GTF_CELL_GRAN;
  unsigned total_pixels = total_active_pixels + hblank;
  unsigned pixel_freq = total_pixels * hfreq_est / 1000;
  int hsync = H_SYNC_PERCENT * total_pixels / 100;
  hsync = (hsync + GTF_CELL_GRAN / 2) / GTF_CELL_GRAN * GTF_CELL_GRAN;
  int hfront_porch = hblank / 2 - hsync;
  memset(m, 0, sizeof *m);
  m->hdisplay = hdisplay_rnd;
  m->hsync_start = hdisplay_rnd + hfront_porch;
  m->hsync_end = m->hsync_start + hsync;
  m->htotal = total_pixels;
  m->vdisplay = vdisplay_rnd;
  m->vsync_start = vdisplay_rnd + GTF_MIN_V_PORCH;
  m->vsync_end = m->vsync_start + V_SYNC_RQD;
  m->vtotal = vtotal_lines;
  m->clock = pixel_freq;
  m->flags = DRM_MODE_FLAG_NHSYNC | DRM_MODE_FLAG_PVSYNC;   // le noyau : NHSYNC|PVSYNC pour les paramètres par défaut
  m->type = DRM_MODE_TYPE_USERDEF;
  m->vrefresh = (unsigned)((m->clock * 1000.0) / (m->htotal * m->vtotal) + 0.5);
  snprintf(m->name, sizeof m->name, "%dx%d", m->hdisplay, m->vdisplay);
  return 0;
}

static double cadence(const drmModeModeInfo *m) {
  return m->htotal && m->vtotal ? m->clock * 1000.0 / ((double)m->htotal * m->vtotal) : 0;
}
static void decrire(const char *quoi, const drmModeModeInfo *m) {
  dire("%s %ux%u à %.4f Hz (%u %u %u %u / %u %u %u %u, %u kHz)", quoi, m->hdisplay, m->vdisplay, cadence(m),
       m->hdisplay, m->hsync_start, m->hsync_end, m->htotal, m->vdisplay, m->vsync_start, m->vsync_end, m->vtotal,
       m->clock);
}
// Deux modes « égaux » : la même chose balayée — timings, horloge et polarités. Le nom et le type n'y sont pour rien.
static int memeMode(const drmModeModeInfo *a, const drmModeModeInfo *b) {
  return a->clock == b->clock && a->hdisplay == b->hdisplay && a->hsync_start == b->hsync_start &&
         a->hsync_end == b->hsync_end && a->htotal == b->htotal && a->vdisplay == b->vdisplay &&
         a->vsync_start == b->vsync_start && a->vsync_end == b->vsync_end && a->vtotal == b->vtotal &&
         (a->flags & ~DRM_MODE_FLAG_PIC_AR_MASK) == (b->flags & ~DRM_MODE_FLAG_PIC_AR_MASK);
}

static const char *TYPES[] = { "Unknown", "VGA", "DVI-I", "DVI-D", "DVI-A", "Composite", "SVIDEO", "LVDS", "Component",
  "DIN", "DP", "HDMI-A", "HDMI-B", "TV", "eDP", "Virtual", "DSI", "DPI", "Writeback", "SPI", "USB" };
static void nomConnecteur(const drmModeConnector *c, char *nom, size_t n) {
  const char *t = c->connector_type < sizeof TYPES / sizeof *TYPES ? TYPES[c->connector_type] : "?";
  snprintf(nom, n, "%s-%u", t, c->connector_type_id);
}

// L'EDID est-il LÀ ? La propriété « EDID » du connecteur porte le bloc lu ; pas de bloc (ou < 128 octets) = pas lu.
static int aUnEdid(int fd, const drmModeConnector *c) {
  drmModeObjectProperties *p = drmModeObjectGetProperties(fd, c->connector_id, DRM_MODE_OBJECT_CONNECTOR);
  int oui = 0;
  for (uint32_t i = 0; p && i < p->count_props && !oui; i++) {
    drmModePropertyRes *pr = drmModeGetProperty(fd, p->props[i]);
    if (pr && !strcmp(pr->name, "EDID") && p->prop_values[i]) {
      drmModePropertyBlobRes *b = drmModeGetPropertyBlob(fd, (uint32_t)p->prop_values[i]);
      oui = b && b->length >= 128;
      if (b) drmModeFreePropertyBlob(b);
    }
    if (pr) drmModeFreeProperty(pr);
  }
  if (p) drmModeFreeObjectProperties(p);
  return oui;
}

// `detect` : refait la sonde du connecteur, EDID compris (ce que fait pxl-connecteurs.sh). Il faut être root.
static void resonder(const char *carte, const char *nom) {
  char chemin[256];
  snprintf(chemin, sizeof chemin, "/sys/class/drm/%s-%s/status", carte, nom);
  FILE *f = fopen(chemin, "w");
  if (!f) { dire("⚠️ impossible d'écrire %s (%s) — pas de nouvelle sonde", chemin, strerror(errno)); return; }
  fputs("detect", f);
  fclose(f);
}

static void dormir(double s) { struct timespec t = { (time_t)s, (long)((s - (time_t)s) * 1e9) }; nanosleep(&t, NULL); }

int main(int argc, char **argv) {
  const char *voulu = NULL, *sansEdid = "800x480@60", *chemin = "/dev/dri/card0";
  int sondes = 3; double attente = 15, tenir = 120;
  for (int i = 1; i < argc; i++) {
    const char *a = argv[i], *v = i + 1 < argc ? argv[i + 1] : NULL;
    if (!strcmp(a, "--gtf") && v) {
      int w, h, r; drmModeModeInfo m;
      if (sscanf(v, "%dx%d@%d", &w, &h, &r) != 3 || gtf(w, h, r, &m)) { fprintf(stderr, "--gtf LxH@R\n"); return 2; }
      printf("%u %u %u %u %u %u %u %u %u %s %s\n", m.hdisplay, m.hsync_start, m.hsync_end, m.htotal, m.vdisplay,
             m.vsync_start, m.vsync_end, m.vtotal, m.clock, m.flags & DRM_MODE_FLAG_NHSYNC ? "-hsync" : "+hsync",
             m.flags & DRM_MODE_FLAG_PVSYNC ? "+vsync" : "-vsync");
      return 0;
    }
    if (!strcmp(a, "--etat")) g_etat = 1;
    else if (!strcmp(a, "--fb")) g_etat = 2;
    else if (!strcmp(a, "--connecteur") && v) { voulu = v; i++; }
    else if (!strcmp(a, "--sans-edid") && v) { sansEdid = v; i++; }
    else if (!strcmp(a, "--sondes") && v) { sondes = atoi(v); i++; }
    else if (!strcmp(a, "--attente") && v) { attente = atof(v); i++; }
    else if (!strcmp(a, "--tenir") && v) { tenir = atof(v); i++; }
    else if (!strcmp(a, "--carte") && v) { chemin = v; i++; }
    else { fprintf(stderr, "option inconnue : %s\n", a); return 0; }
  }

  // 1 · la carte DRM : elle n'existe qu'une fois le pilote sondé (≈ 5,7 s sur un Rock 5B, mesuré le 30/10)
  int fd = -1;
  for (double t = 0; t <= attente; t += 0.1) {
    fd = open(chemin, O_RDWR | O_CLOEXEC);
    if (fd >= 0) break;
    dormir(0.1);
  }
  if (fd < 0) { dire("pas de %s après %.0f s — rien à faire", chemin, attente); return 0; }
  const char *carte = strrchr(chemin, '/') ? strrchr(chemin, '/') + 1 : chemin;

  // 2 · le connecteur : celui qu'on nomme, sinon le premier branché (le Writeback n'est pas un écran)
  drmModeConnector *c = NULL; char nom[32] = "";
  for (double t = 0; t <= attente && !c; t += 0.25) {
    drmModeRes *r = drmModeGetResources(fd);
    for (int i = 0; r && i < r->count_connectors && !c; i++) {
      drmModeConnector *k = drmModeGetConnector(fd, r->connectors[i]);
      if (!k) continue;
      char n[32]; nomConnecteur(k, n, sizeof n);
      int bon = voulu ? !strcmp(n, voulu)
                      : (k->connection == DRM_MODE_CONNECTED && k->connector_type != DRM_MODE_CONNECTOR_WRITEBACK);
      if (bon && k->connection != DRM_MODE_DISCONNECTED) { c = k; snprintf(nom, sizeof nom, "%s", n); }
      else drmModeFreeConnector(k);
    }
    if (r) drmModeFreeResources(r);
    if (!c) dormir(0.25);
  }
  if (!c) {
    if (g_etat == 2) { printf("0 0 -\n"); return 0; }
    dire("aucun écran branché%s%s — rien à faire", voulu ? " sur " : "", voulu ? voulu : ""); return 0;
  }
  if (g_etat == 2) {   // --fb : ce qui est balayé, en une ligne, sans rien sonder ni toucher
    uint32_t id = 0;
    if (c->encoder_id) { drmModeEncoder *e = drmModeGetEncoder(fd, c->encoder_id); if (e) { id = e->crtc_id; drmModeFreeEncoder(e); } }
    drmModeCrtc *k = id ? drmModeGetCrtc(fd, id) : NULL;
    if (k && k->mode_valid) printf("%u %u %ux%u@%.3f\n", id, k->buffer_id, k->mode.hdisplay, k->mode.vdisplay, cadence(&k->mode));
    else printf("%u %u -\n", id, k ? k->buffer_id : 0);
    return 0;
  }

  // 3 · l'EDID — re-sondé avant de conclure qu'il manque (voir l'en-tête : « connected » ≠ « caractérisé »)
  int edid = aUnEdid(fd, c);
  for (int s = 0; !edid && s < sondes; s++) {
    dire("%s : pas d'EDID lu (%d mode(s) de repli du pilote) — nouvelle sonde %d/%d", nom, c->count_modes, s + 1, sondes);
    if (!g_etat) resonder(carte, nom);
    dormir(1.0);
    uint32_t id = c->connector_id; drmModeFreeConnector(c);
    c = drmModeGetConnector(fd, id);
    if (!c) { dire("%s a disparu — rien à faire", nom); return 0; }
    edid = aUnEdid(fd, c);
  }

  drmModeModeInfo veut;
  if (edid) {
    const drmModeModeInfo *pref = NULL;
    for (int k = 0; k < c->count_modes && !pref; k++) if (c->modes[k].type & DRM_MODE_TYPE_PREFERRED) pref = &c->modes[k];
    if (!pref && c->count_modes) pref = &c->modes[0];
    if (!pref) { dire("%s : EDID sans aucun mode — rien à faire", nom); return 0; }
    veut = *pref;
    decrire(nom[0] ? "EDID lu — mode préféré :" : "mode préféré :", &veut);
  } else {
    int w, h, rr;
    if (!strcmp(sansEdid, "aucun") || sscanf(sansEdid, "%dx%d@%d", &w, &h, &rr) != 3 || gtf(w, h, rr, &veut)) {
      dire("%s : pas d'EDID, et pas de mode de repli (« %s ») — on laisse le noyau", nom, sansEdid); return 0;
    }
    decrire("pas d'EDID — repli (GTF, comme video=) :", &veut);
  }

  // 4 · ce qui est balayé MAINTENANT sur ce connecteur
  uint32_t crtcId = 0;
  if (c->encoder_id) { drmModeEncoder *e = drmModeGetEncoder(fd, c->encoder_id); if (e) { crtcId = e->crtc_id; drmModeFreeEncoder(e); } }
  if (!crtcId) {   // aucun CRTC lié : le premier que l'encodeur du connecteur peut servir
    drmModeRes *r = drmModeGetResources(fd);
    for (int k = 0; r && k < c->count_encoders && !crtcId; k++) {
      drmModeEncoder *e = drmModeGetEncoder(fd, c->encoders[k]);
      for (int j = 0; e && j < r->count_crtcs && !crtcId; j++) if (e->possible_crtcs & (1u << j)) crtcId = r->crtcs[j];
      if (e) drmModeFreeEncoder(e);
    }
    if (r) drmModeFreeResources(r);
  }
  if (!crtcId) { dire("%s : aucun CRTC pour ce connecteur — rien à faire", nom); return 0; }
  drmModeCrtc *crtc = drmModeGetCrtc(fd, crtcId);
  if (crtc && crtc->mode_valid && memeMode(&crtc->mode, &veut)) {
    dire("%s : déjà dans ce mode — rien à faire ✅", nom); return 0;
  }
  if (crtc && crtc->mode_valid) decrire("balayé aujourd'hui :", &crtc->mode);
  if (g_etat) { dire("(--etat) le mode serait posé ici — rien n'a été touché"); return 0; }

  // 5 · poser : un tampon noir, le mode, puis rendre le master en GARDANT le tampon (voir l'en-tête)
  if (drmSetMaster(fd) && errno != EINVAL) dire("⚠️ drmSetMaster : %s (on essaie quand même)", strerror(errno));
  struct drm_mode_create_dumb cd = { .width = veut.hdisplay, .height = veut.vdisplay, .bpp = 32 };
  if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd)) { dire("🔴 tampon impossible (%s) — rien posé", strerror(errno)); return 0; }
  struct drm_mode_map_dumb md = { .handle = cd.handle };
  if (!drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md)) {
    void *p = mmap(NULL, cd.size, PROT_WRITE, MAP_SHARED, fd, md.offset);
    if (p != MAP_FAILED) { memset(p, 0, cd.size); munmap(p, cd.size); }   // noir : le fond de Plymouth est sombre aussi
  }
  uint32_t fb = 0;
  if (drmModeAddFB(fd, veut.hdisplay, veut.vdisplay, 24, 32, cd.pitch, cd.handle, &fb)) {
    dire("🔴 drmModeAddFB : %s — rien posé", strerror(errno)); return 0;
  }
  uint32_t conn = c->connector_id;
  if (drmModeSetCrtc(fd, crtcId, fb, 0, 0, &conn, 1, &veut)) {
    dire("🔴 drmModeSetCrtc : %s — le pilote refuse ce mode, on laisse le noyau", strerror(errno)); return 0;
  }
  decrire("✅ posé :", &veut);
  drmDropMaster(fd);   // Plymouth, qui ouvre la carte ensuite, en devient le maître

  // 6 · garder le tampon jusqu'à ce qu'un autre balaie ce CRTC — dans un FILS : systemd (Type=forking) continue
  fflush(stdout);
  pid_t f = fork();
  if (f > 0) return 0;
  if (f < 0) { dire("⚠️ fork : %s — on garde le tampon ici", strerror(errno)); }
  setsid();
  for (double t = 0; t < tenir; t += 0.2) {
    drmModeCrtc *k = drmModeGetCrtc(fd, crtcId);
    int autre = k && k->buffer_id && k->buffer_id != fb;
    if (k) drmModeFreeCrtc(k);
    if (autre) { dire("%s repris par un autre client (tampon %u) — on rend le nôtre", nom, fb); return 0; }
    dormir(0.2);
  }
  dire("⚠️ personne n'a repris %s en %.0f s — on rend le tampon (l'écran revient à la console du noyau)", nom, tenir);
  return 0;
}

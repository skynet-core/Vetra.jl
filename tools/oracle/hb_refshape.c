// T029 shaping reference generator (docs/TEXT_LAYOUT.md §8, protocol
// option 2: maintained external layout engine with recorded version).
// Independent of the code under test: a plain C driver over the system
// libharfbuzz shared library.
//
// Pinned reference library: /usr/lib/x86_64-linux-gnu/libharfbuzz.so.0
//   version 12.3.2 (Ubuntu deb "harfbuzz 12.3.2-2", x86_64-linux-gnu)
// Build (verified 2026-11-09):
//   gcc -I<harfbuzz-12.3.2 headers> hb_refshape.c \
//       /usr/lib/x86_64-linux-gnu/libharfbuzz.so.0 -o hb_refshape
// Output (one line per glyph, buffer order = visual order for RTL):
//   gid=<g> cluster=<c> xadv=<a> xoff=<o> yoff=<y>   (font units)
// Usage: hb_refshape <fontfile> <script_tag_hex> <direction 4|5> <lang> <cp,cp,...>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "harfbuzz/hb.h"

int main(int argc, char **argv) {
  if (argc < 6) { fprintf(stderr, "usage: %s font script dir lang cps\n", argv[0]); return 2; }
  FILE *f = fopen(argv[1], "rb");
  if (!f) { fprintf(stderr, "open %s failed\n", argv[1]); return 1; }
  fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
  char *data = malloc(sz);
  if (fread(data, 1, sz, f) != (size_t)sz) { fprintf(stderr, "read failed\n"); return 1; }
  fclose(f);

  uint32_t script = (uint32_t)strtoul(argv[2], NULL, 16);
  hb_direction_t dir = atoi(argv[3]) == 4 ? HB_DIRECTION_LTR : HB_DIRECTION_RTL;
  hb_language_t lang = hb_language_from_string(argv[4], -1);

  hb_blob_t *blob = hb_blob_create(data, (unsigned)sz, HB_MEMORY_MODE_READONLY, NULL, NULL);
  hb_face_t *face = hb_face_create(blob, 0);
  if (!face) { fprintf(stderr, "face create failed\n"); return 1; }
  hb_font_t *font = hb_font_create(face);

  hb_buffer_t *buf = hb_buffer_create();
  hb_buffer_set_direction(buf, dir);
  hb_buffer_set_script(buf, (hb_script_t)script);
  hb_buffer_set_language(buf, lang);
  char *cps = argv[5];
  char *tok = strtok(cps, ",");
  unsigned i = 0;
  while (tok) {
    uint32_t cp = (uint32_t)strtoul(tok, NULL, 16);
    hb_buffer_add(buf, cp, i++);
    tok = strtok(NULL, ",");
  }
  hb_shape(font, buf, NULL, 0);

  unsigned n = 0;
  hb_glyph_info_t *infos = hb_buffer_get_glyph_infos(buf, &n);
  hb_glyph_position_t *pos = hb_buffer_get_glyph_positions(buf, &n);
  printf("version %s\n", hb_version_string());
  printf("numGlyphs %u\n", hb_face_get_glyph_count(face));
  for (unsigned k = 0; k < n; k++) {
    printf("gid=%u cluster=%u xadv=%d xoff=%d yoff=%d\n",
      infos[k].codepoint, infos[k].cluster,
      pos[k].x_advance, pos[k].x_offset, pos[k].y_offset);
  }
  hb_buffer_destroy(buf);
  hb_font_destroy(font);
  hb_face_destroy(face);
  hb_blob_destroy(blob);
  free(data);
  return 0;
}

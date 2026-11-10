#!/usr/bin/env python3
"""Generate the T029 vendored shaping tables (BMP subset).

Run with these files in the working directory:
  https://unicode.org/Public/16.0.0/ucd/  (Scripts.txt, UnicodeData.txt,
    BidiMirroring.txt) and harfbuzz 15.1.0's src/hb-script-list.h (the
    UAX#24 tag authority the provider uses):
    https://raw.githubusercontent.com/harfbuzz/harfbuzz/15.1.0/src/hb-script-list.h
  python3 gen_hb_tables.py > hb_tables.jl

Sources:
  Scripts.txt          -> _HB_SCRIPT_RANGES   (primary script, UAX#24)
  UnicodeData.txt      -> _HB_BIDI_RANGES     (field 5: Bidi_Category, UAX#9)
  BidiMirroring.txt    -> _HB_MIRROR_PAIRS    (Bidi_Mirroring, UAX#9 L2)
All tables are BMP-only (U+0000..U+FFFF), compressed to sorted,
non-overlapping (start, stop, value) triples / (cp, mirror) pairs,
ascending by start.
"""
import re, sys

def fmt(vals, per=6):
    lines = []
    for i in range(0, len(vals), per):
        chunk = vals[i:i+per]
        lines.append("    " + ", ".join(f"0x{v:04x}" for v in chunk) + ",")
    return "\n".join(lines)

# --- Scripts.txt: primary script (first value), tag = 4 chars ---
out = []
for line in open("Scripts.txt", encoding="utf-8"):
    if not line.strip() or line.startswith("#") or line.startswith("@"):
        continue
    body = line.split("#", 1)[0].strip()
    rng, rest = body.split(";", 1)
    tag = rest.strip().split()[0]
    parts = rng.split("..")
    if len(parts) == 1:
        parts = [parts[0], parts[0]]
    a, b = parts
    lo, hi = int(a, 16), int(b, 16)
    if hi > 0xFFFF:
        hi = 0xFFFF
    if lo > 0xFFFF:
        continue
    out.append((lo, hi, tag))
out.sort(key=lambda t: (t[0], t[1]))
merged = []
for r in out:
    if merged and merged[-1][1] + 1 == r[0] and merged[-1][2] == r[2]:
        merged[-1] = (merged[-1][0], r[1], merged[-1][2])
    else:
        merged.append(r)

# --- UnicodeData.txt field 5 (Bidi_Category), BMP ---
bidi = []
for line in open("UnicodeData.txt", encoding="utf-8"):
    if not line.strip() or line.startswith("#"):
        continue
    f = line.split(";")
    cp = int(f[0], 16)
    if cp > 0xFFFF:
        continue
    bidi.append((cp, cp, f[4]))
# compress
merged_b = []
for r in bidi:
    if merged_b and merged_b[-1][1] + 1 == r[0] and merged_b[-1][2] == r[2]:
        merged_b[-1] = (merged_b[-1][0], r[1], merged_b[-1][2])
    else:
        merged_b.append(r)

# --- BidiMirroring.txt, BMP ---
mirror = []
for line in open("BidiMirroring.txt", encoding="utf-8"):
    if not line.strip() or line.startswith("#"):
        continue
    body = line.split("#", 1)[0].strip()
    rng, m = body.split(";", 1)
    parts = rng.split("..")
    if len(parts) == 1:
        parts = [parts[0], parts[0]]
    a, b = parts
    for cp in range(int(a, 16), int(b, 16) + 1):
        if cp <= 0xFFFF:
            mirror.append((cp, int(m.split()[0], 16)))

# UAX#24 four-letter tags, matched case-insensitively from harfbuzz's
# hb-script-list.h (the tag authority used by the provider, 15.1.0).
import re
hb = {}
for line in open("hb-script-list.h", encoding="utf-8"):
    m = re.search(r"HB_SCRIPT_([A-Z0-9_]+)\s*=\s*HB_TAG\s*\(\s*'(.)','(.)','(.)','(.)'\s*\)", line)
    if m:
        name = m.group(1).lower()
        tag = "".join(m.group(i) for i in range(2, 6))
        if name not in hb:
            hb[name] = tag
missing = []
# UCD name variants whose harfbuzz constant uses the other spelling
# (checked against harfbuzz 15.1.0 hb-script-list.h).
ALIASES = {"canadian_aboriginal": "canadian_syllabics"}
_hb_norm = {k.replace("_", ""): v for k, v in hb.items()}
def name_to_tag(name):
    key = ALIASES.get(name.lower(), name.lower()).replace("_", "")
    if key in _hb_norm:
        return _hb_norm[key]
    missing.append(name)
    return "Zzzz"

def tag_int(tag):
    return (ord(tag[0]) << 24) | (ord(tag[1]) << 16) | (ord(tag[2]) << 8) | ord(tag[3])

def script_flat(triples):
    vals = []
    for a, b, tag in triples:
        vals += [a, b, tag_int(name_to_tag(tag))]
    return vals

def bidi_flat(triples):
    cls = {"L":1,"R":2,"AL":3,"EN":4,"AN":5,"CS":6,"ES":7,"ET":8,"ON":9,"BN":10,
           "NSM":11,"B":12,"S":13,"RLO":14,"LRO":15,"LRE":16,"LRI":17,"RRI":18,
           "PDF":19,"FSI":20,"PDI":21,"WS":22,"RLE":23,"RLI":24}
    vals = []
    for a, b, c in triples:
        vals += [a, b, cls[c]]
    return vals

def mirror_flat(pairs):
    vals = []
    for cp, m in pairs:
        vals += [cp, m]
    return vals

sv = script_flat(merged)
bv = bidi_flat(merged_b)
mv = mirror_flat(mirror)

w = sys.stdout
w.write("const _HB_SCRIPT_RANGES = UInt32[\n")
w.write(fmt(sv) + "\n")
w.write("]\n\n")
w.write("# UAX#9 Bidi_Category (UnicodeData.txt field 5), BMP; class codes:\n")
w.write("#   1=L 2=R 3=AL 4=EN 5=AN 6=CS 7=ES 8=ET 9=ON 10=BN 11=NSM 12=B 13=S 14=RLO 15=LRO 16=LRE 17=LRI 18=RRI 19=PDF 20=FSI 21=PDI 22=WS 23=RLE 24=RLI\n")
w.write("const _HB_BIDI_RANGES = UInt32[\n")
w.write(fmt(bv) + "\n")
w.write("]\n\n")
w.write("const _HB_MIRROR_PAIRS = UInt32[\n")
w.write(fmt(mv, 8) + "\n")
w.write("]\n")

print(f"scripts: {len(merged)} ranges ({len(sv)//3} entries); "
      f"bidi: {len(merged_b)} ranges ({len(bv)//3} entries); "
      f"mirror: {len(mirror)} pairs", file=sys.stderr)
if missing:
    print("UNMAPPED SCRIPT NAMES: " + ", ".join(sorted(set(missing))), file=sys.stderr)

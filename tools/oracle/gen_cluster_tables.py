#!/usr/bin/env python3
"""Regenerate the T028 vendored cluster tables (BMP) from Unicode 16.0.0.

Run with the Unicode 16.0.0 UCD files (DerivedCoreProperties.txt,
UnicodeData.txt — https://unicode.org/Public/16.0.0/ucd/) in the
working directory:  python3 gen_cluster_tables.py > cluster_tables.jl

Provenance (docs/TEXT_LAYOUT.md §3.2):
  _CLUSTER_EXTEND: Grapheme_Extend from DerivedCoreProperties-16.0.0.txt
    (= Me + Mn + Other_Grapheme_Extend) plus U+200D appended (ZWJ is
    category Cf, so the derived property omits it, but UAX#29 GB9a/GB9d
    require it in the Extend class; U+200C appears in the derived
    property already).
  _CLUSTER_MC: general category Mc (spacing combining marks) from
    UnicodeData-16.0.0.txt.
Both BMP-only (<= U+FFFF), compressed to flat [lo, hi, lo, hi, ...]
ascending ranges. The original T028 generation corrupted some ranges
(e.g. Mc 0903 + 093A..093C became 0903..093B) — this script is the
checked-in regeneration (T029).
"""
import io, sys

def collect_ranges(lines):
    out = []
    for ln in lines:
        rng = ln.split("#")[0].split(";")[0].strip()
        if not rng:
            continue
        parts = rng.split("..")
        if len(parts) == 1:
            out.append((int(parts[0], 16), int(parts[0], 16)))
        else:
            out.append((int(parts[0], 16), int(parts[1], 16)))
    return out

def bmp_compress(ranges):
    rs = sorted(set((lo, min(hi, 0xFFFF)) for lo, hi in ranges if lo <= 0xFFFF))
    out = []
    for lo, hi in rs:
        if out and lo <= out[-1][1] + 1:
            out[-1] = (out[-1][0], max(out[-1][1], hi))
        else:
            out.append((lo, hi))
    return out

def flat(rs):
    vals = []
    for lo, hi in rs:
        vals += [lo, hi]
    return vals

def fmt(vals, per=6):
    lines = []
    for i in range(0, len(vals), per):
        chunk = vals[i:i + per]
        lines.append("    " + ", ".join("0x%04x" % v for v in chunk) + ",")
    return "\n".join(lines)

# --- Grapheme_Extend: data lines whose property field is Grapheme_Extend ---
ext_lines = []
for line in io.open("DerivedCoreProperties.txt", encoding="utf-8"):
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    f = s.split(";")
    if len(f) > 1 and f[1].split("#")[0].strip() == "Grapheme_Extend":
        ext_lines.append(f[0])

# --- Mc: UnicodeData field 2 ---
mc_lines = []
for line in io.open("UnicodeData.txt", encoding="utf-8"):
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    f = s.split(";")
    if len(f) > 2 and f[2] == "Mc":
        mc_lines.append(f[0])

ext = bmp_compress(collect_ranges(ext_lines))
mc = bmp_compress(collect_ranges(mc_lines))

has_200c = any(lo <= 0x200C <= hi for lo, hi in ext)
added_200d = not any(lo <= 0x200D <= hi for lo, hi in ext)
if added_200d:
    ext = bmp_compress(ext + [(0x200D, 0x200D)])

sys.stdout.write("const _CLUSTER_EXTEND = [\n")
sys.stdout.write(fmt(flat(ext)) + "\n")
sys.stdout.write("]\n\n")
sys.stdout.write("const _CLUSTER_MC = [\n")
sys.stdout.write(fmt(flat(mc)) + "\n")
sys.stdout.write("]\n")

def inrs(v, rs):
    return any(lo <= v <= hi for lo, hi in rs)

# Devanagari: letters (Lo) in neither table; Anusvara 0902 is Mn ->
# Extend only; 0903 (visarga) is Mc; vowel signs 093A/093E are Mn,
# 093B is Mc; 094D (virama) is Mn -> Extend only.
assert not inrs(0x0905, mc) and not inrs(0x0915, mc) and not inrs(0x0936, mc)
assert inrs(0x094D, ext) and not inrs(0x094D, mc)
assert inrs(0x0903, mc) and inrs(0x093B, mc) and inrs(0x093E, mc)
assert inrs(0x0902, ext) and not inrs(0x0902, mc)
assert not inrs(0x0915, ext) and inrs(0x200D, ext)
assert inrs(0x0301, ext) and not inrs(0x0065, ext)

print("extend: %d ranges (U+200C derived: %s, U+200D appended: %s); "
      "mc: %d ranges" % (len(ext), has_200c, added_200d, len(mc)),
      file=sys.stderr)
print("sanity ok", file=sys.stderr)

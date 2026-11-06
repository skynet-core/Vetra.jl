#!/bin/sh
# Build and run the oracle from the project root.
#
# Requires the pinned source under .reference/ (run
# `julia --startup-file=no --project=. scripts/fetch_upstream.jl` first)
# and the pinned dependency clones under .reference/pkgs/.
set -eu
cd "$(dirname "$0")/../.."
root=$(pwd)
mkdir -p artifacts/oracle
nim c -d:pixieNoSimd \
  --path:.reference/upstream/src \
  --path:.reference/pkgs/vmath/src \
  --path:.reference/pkgs/chroma/src \
  --path:.reference/pkgs/zippy/src \
  --path:.reference/pkgs/flatty/src \
  --path:.reference/pkgs/nimsimd/src \
  --path:.reference/pkgs/bumpy/src \
  --path:.reference/pkgs/crunchy/src \
  -o:artifacts/oracle/emit_fixtures \
  tools/oracle/emit_fixtures.nim
cd "$root"
artifacts/oracle/emit_fixtures "${@:-all}"

# Checksums (recorded alongside the fixtures, per test/README.md).
# .meta gets the hash of its .raw buffer; .tsv/.png get <name>.sha256
# sidecars (no self-referential hash-in-file).
cd "$root/artifacts/oracle"
for f in *.meta; do
  [ -e "${f%.meta}.raw" ] &&
    printf 'sha256_raw=%s\n' \
      "$(sha256sum "${f%.meta}.raw" | cut -d' ' -f1)" >> "$f"
done
for f in *.tsv *.png; do
  [ -e "$f" ] && sha256sum "$f" > "$f.sha256"
done

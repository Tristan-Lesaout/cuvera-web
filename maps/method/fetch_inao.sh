#!/bin/sh
# INAO national AOC parcel delimitation (Licence Ouverte 2.0, data.gouv.fr), file of 2026-11-02 (267 MB zip).
set -e
OUT=${1:-.}
[ -f "$OUT/2026-11-02_delim-parcellaire-aoc-shp.shp" ] && exit 0
curl -s -L -o "$OUT/inao.zip" "https://static.data.gouv.fr/resources/delimitation-parcellaire-des-aoc-viticoles-de-linao/20261102-223943/2026-11-02-delim-parcellaire-aoc-shp.zip"
unzip -o -q "$OUT/inao.zip" -d "$OUT"

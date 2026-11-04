#!/bin/sh
# Data © OpenStreetMap contributors (ODbL 1.0) and the open sources named below. Raw and derived data stay OUT
# of the repo. Overpass mirrors: set OVERPASS=https://overpass.private.coffee/api/interpreter if the main one is busy.
set -e
OUT=${1:-.}
UA="Cuvera-map-research/0.1"
EP=${OVERPASS:-https://overpass-api.de/api/interpreter}
q() { curl -s -A "$UA" --data-urlencode "data=$2" "$EP" -o "$OUT/$1"; }
# Chablis: the Serein from IGN BD TOPO (Licence Ouverte 2.0, Géoplateforme WFS), reduced to one line; INAO areas.
curl -s "https://data.geopf.fr/wfs/ows?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&TYPENAMES=BDTOPO_V3:troncon_hydrographique&OUTPUTFORMAT=application/json&SRSNAME=EPSG:4326&BBOX=47.72,3.70,47.90,3.92,urn:ogc:def:crs:EPSG::4326&COUNT=1000" -o "$OUT/ign_hydro.json"
python3 "$(dirname "$0")/ign_mainline.py" "$OUT/ign_hydro.json" 'le Serein' "$OUT/chablis_rivers.json"
sh "$(dirname "$0")/fetch_inao.sh" "$OUT"
python3 "$(dirname "$0")/inao_extract.py" "$OUT/2026-11-02_delim-parcellaire-aoc-shp" "$OUT/chablis_aoc.json" 'chablis' '^89' 8

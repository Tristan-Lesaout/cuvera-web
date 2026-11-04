#!/bin/sh
# Data © OpenStreetMap contributors (ODbL 1.0) and the open sources named below. Raw and derived data stay OUT
# of the repo. Overpass mirrors: set OVERPASS=https://overpass.private.coffee/api/interpreter if the main one is busy.
set -e
OUT=${1:-.}
UA="Cuvera-map-research/0.1"
EP=${OVERPASS:-https://overpass-api.de/api/interpreter}
q() { curl -s -A "$UA" --data-urlencode "data=$2" "$EP" -o "$OUT/$1"; }
# Barossa: the North Para (OSM), towns and peaks; GI regions © Wine Australia (2021), CC BY 4.0.
q barossa_rivers.json '[out:json][timeout:120];way["waterway"~"^(river|stream)$"]["name"~"North Para|South Para"](-34.80,138.65,-34.30,139.35);out geom;'
q barossa_places.json '[out:json][timeout:60];(node["place"~"^(town|village|hamlet|suburb)$"]["name"~"^(Nuriootpa|Tanunda|Angaston|Lyndoch|Eden Valley|Springton|Williamstown|Rowland Flat|Seppeltsfield|Greenock|Marananga|Bethany|Keyneton|Mount Pleasant)$"](-34.90,138.60,-34.30,139.40);node["natural"="peak"](-34.75,138.85,-34.40,139.25););out;'
# The edition the map was drawn from: Wine Australia's official "Wine Geographical Indications Australia (superseded)"
# item (https://www.arcgis.com/home/item.html?id=ede7ffb0e73b4504a5ed613965b11e0f), feature service 2022v1, CC BY 4.0.
curl -s -G "https://services6.arcgis.com/s8j6JbJJCqmhNgh7/arcgis/rest/services/Wine_Geographical_Indications_Australia_2022v1/FeatureServer/1/query" \
  --data-urlencode "where=GI_NAME IN ('Barossa Valley','Eden Valley')" --data-urlencode "outFields=GI_NAME" \
  --data-urlencode "outSR=4326" --data-urlencode "f=geojson" -o "$OUT/gi_regions.geojson"

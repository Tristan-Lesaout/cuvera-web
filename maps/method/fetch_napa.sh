#!/bin/sh
# Downloads the OpenStreetMap data for the Napa Valley map (read-only Overpass API, one-off use),
# plus the UC Davis AVA boundaries (CC0; used only to check label placement).
# Data © OpenStreetMap contributors, ODbL 1.0: keep raw and derived data OUT of the repo.
# The servers were overloaded on 2026-11-04; these are the smaller queries that succeeded.
set -e
OUT=${1:-.}
UA="Cuvera-map-research/0.1"
EP=${OVERPASS:-https://overpass-api.de/api/interpreter}
q() { curl -s -A "$UA" --data-urlencode "data=$2" "$EP" -o "$OUT/$1"; }
q napa_coast.json '[out:json][timeout:250];way["natural"="coastline"](37.96,-122.80,38.30,-121.85);out geom;'
q napa_river_any.json '[out:json][timeout:120];way["waterway"]["name"="Napa River"](38.05,-122.70,38.65,-122.15);out geom;'
q napa_water.json '[out:json][timeout:120];(relation["natural"="water"](38.06,-122.36,38.32,-122.20);way["natural"="water"]["water"~"^(river|estuary|tidal_channel)$"](38.06,-122.36,38.32,-122.20););out geom;'
q napa_places.json '[out:json][timeout:60];(node["place"~"^(city|town|village|hamlet)$"]["name"~"^(Calistoga|St\\. Helena|Saint Helena|Oakville|Rutherford|Yountville|Napa|American Canyon|Vallejo|Sonoma)$"](37.95,-122.80,38.70,-121.90);node["natural"="peak"]["name"~"^(Mount Saint Helena|Mount Veeder|Atlas Peak|Mount George|Howell Mountain|Diamond Mountain|Spring Mountain)$"](38.0,-122.80,38.75,-122.00););out;'
curl -s -L https://raw.githubusercontent.com/UCDavisLibrary/ava/master/avas_by_state/CA_avas.geojson -o "$OUT/CA_avas.geojson"

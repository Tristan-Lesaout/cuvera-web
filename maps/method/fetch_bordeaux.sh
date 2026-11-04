#!/bin/sh
# Downloads the OpenStreetMap data used by the Bordeaux map (read-only Overpass API, one-off use).
# Data © OpenStreetMap contributors, ODbL 1.0. Keep the raw and derived data OUT of the repo
# (a derived database must itself be ODbL if distributed); only rendered images are kept.
set -e
OUT=${1:-.}
UA="Cuvera-map-research/0.1"
curl -s -A "$UA" --data-urlencode 'data=[out:json][timeout:120];(way["natural"="coastline"](44.35,-1.60,45.70,0.35);way["waterway"="river"]["name"~"^(La Garonne|La Dordogne)$"](44.35,-1.60,45.70,0.35););out geom;' \
  https://overpass-api.de/api/interpreter -o "$OUT/bordeaux_osm.json"
curl -s -A "$UA" --data-urlencode 'data=[out:json][timeout:180];(relation["natural"="water"]["water"~"^(river|estuary|tidal_channel)$"](44.40,-1.50,45.60,0.30);way["natural"="water"]["water"~"^(river|estuary)$"](44.40,-1.50,45.60,0.30););out geom;' \
  https://overpass-api.de/api/interpreter -o "$OUT/bordeaux_water.json"
# Appellation villages, used only to check label placement (check_labels.py).
curl -s -A "$UA" --data-urlencode 'data=[out:json][timeout:60];node["place"~"^(city|town|village)$"]["name"~"^(Bordeaux|Pauillac|Margaux|Saint-Estèphe|Saint-Julien-Beychevelle|Pessac|Léognan|Sauternes|Barsac|Pomerol|Saint-Émilion|Libourne|Créon|Cadillac|Langon|Lesparre-Médoc|Blaye)$"](44.35,-1.60,45.40,0.35);out;' \
  https://overpass-api.de/api/interpreter -o "$OUT/villages.json"

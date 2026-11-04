#!/bin/sh
# Data © OpenStreetMap contributors (ODbL 1.0) and the open sources named below. Raw and derived data stay OUT
# of the repo. Overpass mirrors: set OVERPASS=https://overpass.private.coffee/api/interpreter if the main one is busy.
set -e
OUT=${1:-.}
UA="Cuvera-map-research/0.1"
EP=${OVERPASS:-https://overpass-api.de/api/interpreter}
q() { curl -s -A "$UA" --data-urlencode "data=$2" "$EP" -o "$OUT/$1"; }
# Rioja: the Ebro (Spanish / Basque names) and the seven Rioja valleys; towns and peaks for checks.
q rioja_rivers.json '[out:json][timeout:180];way["waterway"="river"]["name"~"^(Río |Rio )?(Ebro|Tirón|Oja|Najerilla|Iregua|Leza|Jubera|Cidacos|Alhama|Ega|Zadorra|Inglares)$"](42.00,-3.15,42.80,-1.55);out geom;'
q rioja_ebro.json '[out:json][timeout:150];way["waterway"="river"]["name"~"Ebro"](42.00,-3.15,42.80,-1.55);out geom;'
q rioja_places.json '[out:json][timeout:60];(node["place"~"^(city|town|village)$"]["name"~"^(Haro|Laguardia|Logroño|Nájera|Calahorra|Alfaro|Cenicero|Elciego|Labastida|Briones|San Asensio|Fuenmayor|Arnedo|Aldeanueva de Ebro|Santo Domingo de la Calzada|Ezcaray|Lodosa|Miranda de Ebro)$"](42.00,-3.20,42.80,-1.50);node["natural"="peak"]["name"~"Toloño|Cantabria|León Dormido|Codés"](42.50,-3.10,42.80,-2.10););out;'

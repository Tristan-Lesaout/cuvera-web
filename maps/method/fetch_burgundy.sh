#!/bin/sh
# Data © OpenStreetMap contributors (ODbL 1.0) and the open sources named below. Raw and derived data stay OUT
# of the repo. Overpass mirrors: set OVERPASS=https://overpass.private.coffee/api/interpreter if the main one is busy.
set -e
OUT=${1:-.}
UA="Cuvera-map-research/0.1"
EP=${OVERPASS:-https://overpass-api.de/api/interpreter}
q() { curl -s -A "$UA" --data-urlencode "data=$2" "$EP" -o "$OUT/$1"; }
# Burgundy: the Saône and towns from OSM; appellation areas from the INAO national file (Licence Ouverte 2.0).
q burgundy_rivers.json '[out:json][timeout:180];way["waterway"="river"]["name"~"^(La )?Saône$"](45.80,3.40,48.00,5.90);out geom;'
q burgundy_places.json '[out:json][timeout:60];node["place"~"^(city|town|village)$"]["name"~"^(Dijon|Beaune|Nuits-Saint-Georges|Gevrey-Chambertin|Santenay|Chalon-sur-Saône|Mercurey|Tournus|Mâcon|Villefranche-sur-Saône|Chablis|Fleurie|Meursault|Vosne-Romanée|Givry|Rully|Montagny-lès-Buxy|Solutré-Pouilly)$"](45.80,3.40,48.00,5.90);out;'
sh "$(dirname "$0")/fetch_inao.sh" "$OUT"
python3 "$(dirname "$0")/inao_extract.py" "$OUT/2026-11-02_delim-parcellaire-aoc-shp" "$OUT/burgundy_aoc.json" 'Marsannay|Fixin|Gevrey|Morey|Chambolle|Vougeot|Vosne|Nuits|Chambertin|Musigny|Bonnes.Mares|Clos de|Richebourg|Romanée|Tâche|chezeaux|Ladoix|Aloxe|Corton|Pernand|Savigny|Chorey|Beaune|Pommard|Volnay|Monthelie|Auxey|Saint-Romain|Meursault|Puligny|Chassagne|Montrachet|Saint-Aubin|Santenay|Maranges|Blagny|Bouzeron|Rully|Mercurey|Givry|Montagny|Pouilly|Saint-Véran|Viré|Mâcon|Brouilly|Chénas|Chiroubles|Fleurie|Juliénas|Morgon|Moulin-à-Vent|Régnié|Saint-Amour|^Beaujolais' '^(21|71|69)' 60
python3 "$(dirname "$0")/inao_extract.py" "$OUT/2026-11-02_delim-parcellaire-aoc-shp" "$OUT/chablis_aoc.json" 'chablis' '^89' 8

# Base-map geometry for any Explore region (research tool; output is NOT stored in the repo, ODbL).
# Usage: python3 build_map.py <region-config.json> <data-dir> <out-scene.json>
# The config gives the map's own projection
#   x = x0 + (lon - lon0) * kx,  y = y0 + (lat0 - lat) * ky   (340-wide grid, height h),
# the OSM input files, the river names, and the flood-fill seeds for sea / estuary.
import json, math, re, sys

cfg = json.load(open(sys.argv[1])); src = sys.argv[2]; out = sys.argv[3]
P = cfg["projection"]
def load(name):
    try: return json.load(open(f"{src}/{name}"))
    except (FileNotFoundError, json.JSONDecodeError): return {"elements": []}
_seen = set()
osm = {"elements": [e for f in cfg["lineFiles"] for e in load(f)["elements"]
                    if not ((e["type"], e["id"]) in _seen or _seen.add((e["type"], e["id"])))]}
wat = {"elements": [e for f in cfg.get("waterFiles", []) for e in load(f)["elements"]]}

def proj(p): return (P["x0"] + (p["lon"] - P["lon0"]) * P["kx"], P["y0"] + (P["lat0"] - p["lat"]) * P["ky"])
def key(p): return (round(p["lat"], 7), round(p["lon"], 7))

def dp(pts, tol):
    if len(pts) < 3: return pts
    (x1, y1), (x2, y2) = pts[0], pts[-1]
    if (x1, y1) == (x2, y2):  # closed ring: split so the chord is not degenerate
        h = len(pts) // 2
        return dp(pts[: h + 1], tol)[:-1] + dp(pts[h:], tol)
    L = math.hypot(x2 - x1, y2 - y1); i, m = 0, -1.0
    for k in range(1, len(pts) - 1):
        x0, y0 = pts[k]; d = abs((y2 - y1) * x0 - (x2 - x1) * y0 + x2 * y1 - y2 * x1) / L
        if d > m: i, m = k, d
    return [pts[0], pts[-1]] if m <= tol else dp(pts[: i + 1], tol)[:-1] + dp(pts[i:], tol)

def chaikin(pts, n=2):
    # Corner-cutting smoothing; endpoints kept. Each pass moves points by at most a
    # quarter of a segment, so after a 0.25-unit DP the drift stays well under 1 grid unit.
    for _ in range(n):
        if len(pts) < 3: return pts
        q = [pts[0]]
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            q += [(0.75 * ax + 0.25 * bx, 0.75 * ay + 0.25 * by), (0.25 * ax + 0.75 * bx, 0.25 * ay + 0.75 * by)]
        q.append(pts[-1]); pts = q
    return pts

def chain(ways):
    # Join ways that share end nodes into the longest possible polylines.
    ways = [w[:] for w in ways if len(w) > 1]; lines = []
    while ways:
        cur = ways.pop(0); grown = True
        while grown:
            grown = False
            for i, w in enumerate(ways):
                if key(w[0]) == key(cur[-1]): cur += w[1:]
                elif key(w[-1]) == key(cur[-1]): cur += w[::-1][1:]
                elif key(w[-1]) == key(cur[0]): cur = w + cur[1:]
                elif key(w[0]) == key(cur[0]): cur = w[::-1] + cur[1:]
                else: continue
                ways.pop(i); grown = True; break
        lines.append(cur)
    return lines

groups = cfg.get("riverGroups") or [{"names": cfg["rivers"], "width": cfg.get("riverWidth", 4.0)}]
cfg["rivers"] = [n for g in groups for n in g["names"]]
coast, rivers = [], {r: [] for r in cfg["rivers"]}
for e in osm["elements"]:
    t = e["tags"]
    if t.get("natural") == "coastline": coast.append(e["geometry"])
    else:
        nm = t.get("name", "")
        for r in cfg["rivers"]:
            pat = cfg.get("riverPatterns", {}).get(r)
            if re.search(pat, nm) if pat else ((re.sub(r"^(La |Le |Río |Rio |River )", "", nm) == r or nm == r) if cfg.get("exactRiverNames") else r in nm):
                rivers[r].append(e["geometry"])

coast_lines = [dp([proj(p) for p in l], 0.12) for l in chain(coast)]
tol_of = {n: g.get("tolerance", 0.25) for g in groups for n in g["names"]}
river_lines = {k: [chaikin(dp([proj(p) for p in l], tol_of[k])) for l in chain(v)] for k, v in rivers.items()}
# Optional: drop short side-channel / island fragments that double up on a main river (they read as blobs).
if cfg.get("minLineLength"):
    def length(l): return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(l, l[1:]))
    river_lines = {k: [l for l in v if length(l) >= cfg["minLineLength"]] for k, v in river_lines.items()}

# Keep only water areas that belong to the Gironde / Garonne / Dordogne: any vertex within
# 3 grid units of a main-river centreline, or a named junction polygon. This drops the
# minor tributaries and the stray fragment in the first prototype.
cells = {}
for ls in river_lines.values():
    for l in ls:
        for x, y in l: cells.setdefault((int(x // 3), int(y // 3)), []).append((x, y))
def near_river(x, y, r=3.0):
    cx, cy = int(x // 3), int(y // 3)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for px, py in cells.get((cx + dx, cy + dy), []):
                if (px - x) ** 2 + (py - y) ** 2 <= r * r: return True
    return False

areas, kept, dropped = [], 0, 0
for e in wat["elements"]:
    name = e.get("tags", {}).get("name", "")
    # Optional per-region filter (e.g. Napa: skip salt ponds and reservoirs beside the river).
    if "waterTypes" in cfg and e.get("tags", {}).get("water") not in cfg["waterTypes"]:
        dropped += 1; continue
    # Optional explicit curation by OSM id ("w<id>" / "r<id>"), checked against the extents listing.
    if "includeAreaIds" in cfg:
        if f"{e['type'][0]}{e['id']}" in cfg["includeAreaIds"]:
            rings = [dp([proj(p) for p in r], 0.1) for r in ([e["geometry"]] if e["type"] == "way" else chain([m["geometry"] for m in e["members"] if m.get("geometry")]))]
            areas.append([[[round(x, 2), round(y, 2)] for x, y in r] for r in rings if len(r) >= 3]); kept += 1
        else: dropped += 1
        continue
    rings_raw = [e["geometry"]] if e["type"] == "way" else [m["geometry"] for m in e["members"] if m.get("geometry")]
    if e["type"] == "relation": rings_raw = chain(rings_raw)
    rings = [dp([proj(p) for p in r], 0.1) for r in rings_raw]
    rings = [r for r in rings if len(r) >= 3]
    if not rings: continue
    pts = [p for r in rings for p in r]
    in_frame = any(-5 <= x <= 345 and -5 <= y <= cfg["h"] + 5 for x, y in pts)
    big = max(abs(sum(r[i][0] * r[(i + 1) % len(r)][1] - r[(i + 1) % len(r)][0] * r[i][1] for i in range(len(r)))) / 2 for r in rings) >= 2.0
    # Slivers under 2 grid units² (tributary mouths, quays) read as hairlines: the river stroke already covers them.
    sample = pts[:: max(1, len(pts) // 60)]
    along = sum(near_river(x, y) for x, y in sample) / len(sample)
    # Default: any vertex near a main river. Optional stricter rule (areaNearFraction) keeps only areas
    # that run ALONG the river, dropping sloughs and side channels that merely touch it.
    need = cfg.get("areaNearFraction")
    alongs = along >= need if need else along > 0
    keep = in_frame and (name.startswith("Jonction") or (big and alongs))
    if keep: areas.append([[[round(x, 2), round(y, 2)] for x, y in r] for r in rings]); kept += 1
    else: dropped += 1

r2 = lambda ls: [[[round(x, 2), round(y, 2)] for x, y in l] for l in ls]
scene = {
    "w": 340, "h": cfg["h"], "scale": 4, "bg": "#E7EAED", "seaColor": "#D6DEE3",
    "coast": r2(coast_lines), "seaSeeds": [s["at"] for s in cfg["seeds"]], "seedColors": [s["color"] for s in cfg["seeds"]],
    "waterAreas": areas, "areaColor": "#A9BCC8",
    "rivers": [{"color": "#A9BCC8", "width": g["width"], "lines": r2([l for r in g["names"] for l in river_lines[r]])} for g in groups],
    "cities": [], "labels": [],
}
if cfg.get("eraseRects"): scene["eraseRects"] = cfg["eraseRects"]

# Wine-region areas (optional): INAO extracts (inao_extract.py) or GeoJSON (e.g. Wine Australia GIs),
# each entry with filters and a fill colour. Drawn under the water, as soft tints.
def centroid(rings):
    pts = [p for r in rings for p in r]; return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
tints = []
for t in cfg.get("tintAreas", []):
    d = json.load(open(f"{src}/{t['file']}"))
    feats = []
    if "features" in d and d["features"] and "rings" in d["features"][0]:          # INAO extract
        for f in d["features"]:
            if t.get("app") and not re.search(t["app"], f["app"]): continue
            if t.get("appExclude") and re.search(t["appExclude"], f["app"]): continue
            if t.get("denom") and not re.search(t["denom"], f["denom"]): continue
            if t.get("insee") and not re.match(t["insee"], f["insee"]): continue
            lon, lat = centroid(f["rings"])
            if "latMin" in t and lat < t["latMin"]: continue
            if "latMax" in t and lat >= t["latMax"]: continue
            feats.append([[{"lon": p[0], "lat": p[1]} for p in r] for r in f["rings"]])
    else:                                                                         # GeoJSON
        for f in d["features"]:
            if any(str(f["properties"].get(k)) != str(v) for k, v in t.get("properties", {}).items()): continue
            g = f["geometry"]; polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
            for poly in polys: feats.append([[{"lon": c[0], "lat": c[1]} for c in ring] for ring in poly])
    shapes = []
    for rings in feats:
        pr = [dp([proj(p) for p in r], t.get("tolerance", 0.15)) for r in rings]
        pr = [[[round(x, 2), round(y, 2)] for x, y in r] for r in pr if len(r) >= 3]
        if pr and any(-20 <= x <= 360 and -20 <= y <= cfg["h"] + 20 for r in pr for x, y in r): shapes.append(pr)
    tints.append({"color": t["color"], "shapes": shapes, "what": t.get("what", ""), **{k: t[k] for k in ("close", "grow") if k in t}})
    print(f"tint {t.get('what', t['file'])}: {len(shapes)} shapes")
if tints: scene["tintAreas"] = tints
json.dump(scene, open(out, "w"))
print(f"coast lines {len(coast_lines)}; " + ", ".join(f"{r} {len(river_lines[r])}" for r in cfg["rivers"]) +
      f" chained lines; water areas kept {kept}, dropped {dropped}")

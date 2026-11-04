# Extract INAO AOC delimitations (Licence Ouverte / Etalab 2.0, "Source: INAO") from the
# national shapefile, without GIS libraries: reads .shp/.shx/.dbf directly, converts
# Lambert-93 (EPSG:2154) to WGS84 and simplifies. Research tool.
# Usage: python3 inao_extract.py <shp-basename> <out.json> <app-regex> [<insee-prefix-regex>] [<tolerance-m>]
#   app-regex is matched against the "app" (appellation) and "denom" (denomination) fields.
import json, math, re, struct, sys

base, out, app_re = sys.argv[1], sys.argv[2], re.compile(sys.argv[3], re.I)
insee_re = re.compile(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] else None
tol = float(sys.argv[5]) if len(sys.argv) > 5 else 15.0

# --- Lambert-93 -> WGS84 (GRS80; RGF93 = WGS84 within ~1 m, fine at map scale) ---
a, f = 6378137.0, 1 / 298.257222101
e = math.sqrt(2 * f - f * f)
lat1, lat2, lat0, lon0 = map(math.radians, (44.0, 49.0, 46.5, 3.0))
FE, FN = 700000.0, 6600000.0
def m(p): return math.cos(p) / math.sqrt(1 - (e * math.sin(p)) ** 2)
def t(p): return math.tan(math.pi / 4 - p / 2) / ((1 - e * math.sin(p)) / (1 + e * math.sin(p))) ** (e / 2)
n = (math.log(m(lat1)) - math.log(m(lat2))) / (math.log(t(lat1)) - math.log(t(lat2)))
F = m(lat1) / (n * t(lat1) ** n)
rho0 = a * F * t(lat0) ** n
def to_wgs(x, y):
    dx, dy = x - FE, rho0 - (y - FN)
    rho = math.copysign(math.hypot(dx, dy), n)
    tt = (rho / (a * F)) ** (1 / n)
    lon = math.atan2(dx, dy) / n + lon0
    phi = math.pi / 2 - 2 * math.atan(tt)
    for _ in range(8):
        phi = math.pi / 2 - 2 * math.atan(tt * ((1 - e * math.sin(phi)) / (1 + e * math.sin(phi))) ** (e / 2))
    return math.degrees(lon), math.degrees(phi)

def dp(pts, tol):
    if len(pts) < 3: return pts
    (x1, y1), (x2, y2) = pts[0], pts[-1]
    if (x1, y1) == (x2, y2):
        h = len(pts) // 2
        return dp(pts[: h + 1], tol)[:-1] + dp(pts[h:], tol)
    L = math.hypot(x2 - x1, y2 - y1); i, mx = 0, -1.0
    for k in range(1, len(pts) - 1):
        x0, y0 = pts[k]; d = abs((y2 - y1) * x0 - (x2 - x1) * y0 + x2 * y1 - y2 * x1) / L
        if d > mx: i, mx = k, d
    return [pts[0], pts[-1]] if mx <= tol else dp(pts[: i + 1], tol)[:-1] + dp(pts[i:], tol)

# --- DBF ---
dbf = open(base + ".dbf", "rb"); hdr = dbf.read(32)
nrec = struct.unpack("<I", hdr[4:8])[0]; hlen = struct.unpack("<H", hdr[8:10])[0]; rlen = struct.unpack("<H", hdr[10:12])[0]
fields = []
while True:
    fd = dbf.read(32)
    if fd[0] == 0x0D: break
    fields.append((fd[:11].split(b"\0")[0].decode(), fd[16]))
def record(i):
    dbf.seek(hlen + i * rlen); r = dbf.read(rlen); off = 1; d = {}
    for name, l in fields: d[name] = r[off:off + l].decode("utf-8", "replace").strip(); off += l
    return d
# --- SHX / SHP ---
shx = open(base + ".shx", "rb").read(); shp = open(base + ".shp", "rb")
feats, total_pts, kept_pts = [], 0, 0
for i in range(nrec):
    d = record(i)
    if not (app_re.search(d.get("app", "")) or app_re.search(d.get("denom", ""))): continue
    if insee_re and not insee_re.match(d.get("insee", "")): continue
    off = struct.unpack(">i", shx[100 + i * 8: 104 + i * 8])[0] * 2
    shp.seek(off + 8); stype = struct.unpack("<i", shp.read(4))[0]
    if stype != 5: continue
    shp.read(32); nparts, npts = struct.unpack("<ii", shp.read(8))
    parts = list(struct.unpack(f"<{nparts}i", shp.read(4 * nparts))) + [npts]
    xy = struct.unpack(f"<{2 * npts}d", shp.read(16 * npts))
    rings = []
    for p in range(nparts):
        ring = [(xy[2 * k], xy[2 * k + 1]) for k in range(parts[p], parts[p + 1])]
        total_pts += len(ring)
        s = dp(ring, tol)
        if len(s) >= 4:
            rings.append([[round(c, 6) for c in to_wgs(x, y)] for x, y in s]); kept_pts += len(s)
    if rings:
        feats.append({"app": d["app"], "denom": d["denom"], "commune": d["nomcom"], "insee": d["insee"], "rings": rings})
json.dump({"source": "INAO, Délimitation parcellaire des AOC viticoles (Licence Ouverte 2.0), file 2026-11-02", "features": feats}, open(out, "w"), ensure_ascii=False)
apps = {}
for f in feats: apps[f["app"]] = apps.get(f["app"], 0) + 1
print(f"{len(feats)} records, points {total_pts} -> {kept_pts} (tolerance {tol} m); appellations: {apps}")

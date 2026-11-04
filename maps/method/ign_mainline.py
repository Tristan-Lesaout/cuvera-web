# One clean river line from IGN BD TOPO sections (Licence Ouverte 2.0): the network can carry a virtual
# centreline through a wide bed AND the real side arms, which draw as doubled strands at map scale. This
# builds a graph of the main flowing network and keeps the shortest path between its two extreme ends.
# Usage: python3 ign_mainline.py <ign.geojson> <river toponym> <out osm-like json> <south|north first>
import heapq, json, math, sys

src, name, out = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(src))
segs = []
for f in d["features"]:
    p = f["properties"]
    if p.get("cpx_toponyme_de_cours_d_eau") != name or not p.get("reseau_principal_coulant"): continue
    g = f["geometry"]
    for line in ([g["coordinates"]] if g["type"] == "LineString" else g["coordinates"]):
        segs.append([(c[0], c[1]) for c in line])
key = lambda c: (round(c[0], 6), round(c[1], 6))
def dist(a, b): return math.hypot((a[0] - b[0]) * math.cos(math.radians(a[1])), a[1] - b[1])
graph = {}
for i, s in enumerate(segs):
    L = sum(dist(a, b) for a, b in zip(s, s[1:]))
    u, v = key(s[0]), key(s[-1])
    graph.setdefault(u, []).append((v, L, i, False)); graph.setdefault(v, []).append((u, L, i, True))
nodes = list(graph)
start = min(nodes, key=lambda n: n[1])   # southernmost end
goal = max(nodes, key=lambda n: n[1])    # northernmost end
best, prev, pq = {start: 0.0}, {}, [(0.0, start)]
while pq:
    dcur, u = heapq.heappop(pq)
    if u == goal: break
    if dcur > best.get(u, 1e18): continue
    for v, L, i, rev in graph[u]:
        nd = dcur + L
        if nd < best.get(v, 1e18): best[v] = nd; prev[v] = (u, i, rev); heapq.heappush(pq, (nd, v))
path, n = [], goal
while n != start:
    u, i, rev = prev[n]; s = segs[i]; path.append(s if not rev else s[::-1]); n = u
line = []
for s in reversed(path): line += s if not line else s[1:]
json.dump({"source": f"IGN BD TOPO (Licence Ouverte 2.0), {name}: shortest path through the main flowing network",
           "elements": [{"type": "way", "id": 1, "tags": {"waterway": "river", "name": name.replace("le ", "").replace("la ", "")}, "geometry": [{"lat": c[1], "lon": c[0]} for c in line]}]},
          open(out, "w"))
print(f"{len(segs)} sections -> 1 line of {len(line)} points ({len(path)} sections)")

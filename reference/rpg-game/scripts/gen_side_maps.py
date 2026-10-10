"""Phase 15a: sinh 50 bản đồ phụ (priv/maps/side_XX.json), cấp quái 1..50 rải đều, 10 nhóm chủ đề × 5 bản đồ.

- Bản đồ i (1..50) có quái cấp i, i+1, i+2 (`SIDE_MONSTERS` trong priv/game_data/side.json).
- Trong nhóm: cổng trái về bản đồ trước, cổng phải sang bản đồ sau. Bản đồ đầu nhóm có cổng trái về một bản đồ
  hiện có (PARENTS), và bản đồ hiện có đó được thêm một cổng (ô `O`) ở mép phải dẫn vào nhóm.
- Ngẫu nhiên có hạt giống cố định (chạy lại ra y hệt). Ô đi được nhưng không tới được từ cổng bị lấp.
Chạy: python3 scripts/gen_side_maps.py
"""
import json, os, random
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPS = os.path.join(ROOT, "priv/maps")
W, H = 24, 16
MID = H // 2
WALK = set(".,:*DAO><")

# (tên nhóm, nền ô `.`, nền trận, tường viền, vật cản [(ký tự, tỉ lệ)], trang trí đi được, thu thập, bản đồ cha)
GROUPS = [
    ("Đồng Cỏ Xanh", "floors/forest", "forest", "T", [("T", 0.05)], ",*", ["herb"], "forest_1"),
    ("Rừng Thưa", "floors/forest", "forest", "T", [("T", 0.12), ("Y", 0.05), ("~", 0.02)], ",", ["herb"], "forest_2"),
    ("Gò Kiến Đỏ", "floors/camp", "camp", "R", [("R", 0.1)], ":", ["ore"], "camp_1"),
    ("Đầm Sương", "floors/swamp", "swamp", "T", [("~", 0.14), ("K", 0.05)], ",", ["herb", "herb_rare"], "camp_2"),
    ("Cao Nguyên Tuyết", "floors/mountain", "mountain", "R", [("R", 0.12), ("~", 0.03)], ":", ["ore"], "graveyard_2"),
    ("Thung Lũng U Linh", "floors/graveyard", "graveyard", "K", [("K", 0.1), ("S", 0.04)], ":", ["herb_rare"], "mountain_1"),
    ("Mộ Cổ Hoang", "floors/graveyard", "graveyard", "#", [("I", 0.06), ("S", 0.06)], "", ["ore_rare"], "mountain_2"),
    ("Lò Nguyên Tố", "floors/lair", "lair", "R", [("~", 0.1), ("R", 0.07)], ":", ["ore_rare"], "swamp_2"),
    ("Đỉnh Khổng Lồ", "floors/mountain", "mountain", "R", [("R", 0.14), ("Y", 0.03)], ":", ["ore", "ore_rare"], "lair_1"),
    ("Vực Quỷ", "floors/lair", "lair", "#", [("~", 0.1), ("I", 0.05)], "", ["ore_rare", "herb_rare"], "lair_2"),
]


def sid(i):
    return "side_%02d" % i


def bfs(grid, start):
    seen = {start}
    q = deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H and (nx, ny) not in seen and grid[ny][nx] in WALK:
                seen.add((nx, ny))
                q.append((nx, ny))
    return seen


def make(i, g, gi, k):
    name, floor, theme, wall, obst, deco, gather, parent = g
    rnd = random.Random(1500 + i)
    grid = [[wall if x in (0, W - 1) or y in (0, H - 1) else "." for x in range(W)] for y in range(H)]
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            r = rnd.random()
            acc = 0
            for ch, p in obst:
                acc += p
                if r < acc:
                    grid[y][x] = ch
                    break
            else:
                if deco and rnd.random() < 0.18:
                    grid[y][x] = rnd.choice(deco)
    # đường đất uốn lượn từ cổng trái sang cổng phải
    y = MID
    for x in range(1, W - 1):
        grid[y][x] = ":" if deco != "" else "."
        if 2 < x < W - 3 and rnd.random() < 0.3:
            ny = max(3, min(H - 4, y + rnd.choice((-1, 1))))
            grid[ny][x] = grid[y][x]
            y = ny
    for yy in range(min(y, MID), max(y, MID) + 1):
        grid[yy][W - 2] = ":" if deco != "" else "."
    for dx in (1, 2):
        grid[MID][dx] = "."
        grid[MID][W - 1 - dx] = "."
    portals = []
    first, last = k == 0, k == 4
    grid[MID][0] = "O"
    back = parent if first else sid(i - 1)
    portals.append({"at": [0, MID], "to": back, "spawn": None})
    if not last:
        grid[MID][W - 1] = "O"
        portals.append({"at": [W - 1, MID], "to": sid(i + 1), "spawn": [1, MID]})
    # lấp ô không tới được từ cổng vào
    ok = bfs(grid, (1, MID))
    for yy in range(1, H - 1):
        for xx in range(1, W - 1):
            if grid[yy][xx] in WALK and (xx, yy) not in ok:
                grid[yy][xx] = obst[0][0]
    lv = i
    spawns = [{"monster": m, "max": 4, "respawn": 25} for m in species_for(lv)]
    return {
        "id": sid(i),
        "name": f"{name} {k + 1}",
        "zone": None,
        "side": True,
        "theme": theme,
        "floor": floor,
        "tiles": ["".join(r) for r in grid],
        "portals": portals,
        "spawns": spawns,
        "gather": [{"item": it, "max": 2, "respawn": 70} for it in gather],
        "npcs": [],
    }


SIDE = json.load(open(os.path.join(ROOT, "priv/game_data/side.json"), encoding="utf-8"))["SIDE_MONSTERS"]
BY_LV = {m["level"]: m["id"] for m in SIDE}


def species_for(lv):
    return [BY_LV[l] for l in (lv, lv + 1, lv + 2)]


def add_parent_portal(parent_id, to, spawn_in_side):
    """Thêm cổng `O` ở mép phải bản đồ cha (nếu chưa có), trả về ô đứng khi quay về."""
    path = os.path.join(MAPS, parent_id + ".json")
    m = json.load(open(path, encoding="utf-8"))
    rows = [list(r) for r in m["tiles"]]
    h, w = len(rows), len(rows[0])
    for p in m["portals"]:
        if p["to"] == to:
            return [p["at"][0] - 1, p["at"][1]]
    taken = {tuple(p["at"]) for p in m["portals"]}
    npcs = {tuple(n["at"]) for n in m.get("npcs", [])}
    order = sorted(range(1, h - 1), key=lambda y: abs(y - h // 2))
    for y in order:
        x = w - 1
        if (x, y) in taken or rows[y][x - 1] not in WALK or (x - 1, y) in npcs:
            continue
        if any(abs(y - ty) < 3 and tx == x for tx, ty in taken):
            continue
        rows[y][x] = "O"
        m["tiles"] = ["".join(r) for r in rows]
        m["portals"].append({"at": [x, y], "to": to, "spawn": spawn_in_side})
        with open(path, "w", encoding="utf-8") as f:
            json.dump(m, f, ensure_ascii=False, indent=2)
            f.write("\n")
        return [x - 1, y]
    raise SystemExit(f"không chỗ đặt cổng ở {parent_id}")


def main():
    n = 0
    for gi, g in enumerate(GROUPS):
        for k in range(5):
            i = gi * 5 + k + 1
            m = make(i, g, gi, k)
            if k == 0:
                m["portals"][0]["spawn"] = add_parent_portal(g[7], sid(i), [1, MID])
            else:
                m["portals"][0]["spawn"] = [W - 2, MID]
            with open(os.path.join(MAPS, sid(i) + ".json"), "w", encoding="utf-8") as f:
                json.dump(m, f, ensure_ascii=False, indent=2)
                f.write("\n")
            n += 1
    print(n, "bản đồ phụ")


main()

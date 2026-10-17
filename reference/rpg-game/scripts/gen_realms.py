"""Phase 6 (B-30): 10 vùng đất chuyển sinh (priv/maps/realm_XX.json) + quái (priv/game_data/realms.json).

- Vùng k (1..10) cần chuyển sinh ≥ k và cấp ≥ RULES.realms.min_level; quái hiện cấp 50+10k−8 … 50+10k (chúa tể).
- Sức mạnh theo phương án (a) anh chốt: giữ cấp tối đa 50, chỉ số quái tính ở cấp `stat_level` 50 × `mult`
  (1 + mult_per_realm × k; chúa tể × boss_mult); riêng công nhân (1 + atk_mult_per_realm × k) (× boss_mult); kinh nghiệm tính ở stat_level × (1 + xp_mult_per_realm × k) (× boss_mult). Rơi đồ quý hơn theo `rich` = k (RULES.realms.loot_per_realm).
- Hình quái: tô lại từ hình CC0 sẵn có (e2e/tint_sprites.mjs đọc danh sách REALM_TINTS trong realms.json).
- Cổng: vùng k trái → vùng k−1 (vùng 1 → Làng, một chiều), phải → vùng k+1. Mỗi vùng một Đài Phúc Lành.
- Mỗi vùng `RULES.realms.maps_per_realm` bản đồ (DECISIONS "Vùng chuyển sinh 5 bản đồ"): bản đồ 1 `realm_KK` là cửa vào
  (cổng vùng trước / sau, Đài Phúc Lành), cổng mép dưới vào nhánh `realm_KK_2` → … → `realm_KK_5`. Bản đồ thứ d (0…4 tính
  từ bản đồ 1) đánh như vùng k + depth_step × d: hệ số máu / công / kinh nghiệm, `rich` (rơi đồ), ngọc và cấp hiện nội suy
  giữa vùng k và k + 1. Quái bản đồ 1 giữ id cũ, bản đồ sau `r<k>_<loài>_<d+1>`. Chúa tể (`lord: true`) ở bản đồ cuối.
Chạy: python3 scripts/gen_realms.py  rồi  node e2e/tint_sprites.mjs realm
"""
import json, os, random
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPS = os.path.join(ROOT, "priv/maps")
RULES = json.load(open(os.path.join(ROOT, "priv/game_data/rules.json"), encoding="utf-8"))["RULES"]["realms"]
W, H = 26, 16
MID = H // 2
WALK = set(".,:*DAO><W")
DOWN = W // 2

# (tên, nền, theme, tường, vật cản, trang trí, thu thập, nguyên tố, [(hình gốc, tên quái)] ×3, (hình gốc, tên chúa tể), bộ lọc tô màu)
REALMS = [
    ("Hoang Mạc Xích Viêm", "floors/lair", "lair", "R", [("R", 0.08), ("~", 0.06)], ":", ["ore_rare"], "fire",
     [("fire_elemental", "Hỏa Linh Xích Viêm"), ("hell_hound", "Chó Ngục Viêm"), ("red_devil", "Quỷ Đỏ Sa Mạc")],
     ("balrug", "Chúa Tể Xích Viêm"), "hue-rotate(-15deg) saturate(1.6) brightness(1.05)"),
    ("Băng Nguyên Vĩnh Cửu", "floors/mountain", "mountain", "R", [("R", 0.1), ("~", 0.05)], ":", ["ore"], "ice",
     [("ice_beast", "Băng Thú Vĩnh Cửu"), ("frost_giant", "Người Khổng Lồ Sương"), ("polar_bear", "Gấu Tuyết Cổ")],
     ("ice_dragon", "Băng Long Vĩnh Cửu"), "saturate(1.3) brightness(1.2) contrast(1.1)"),
    ("Rừng Lôi Phong", "floors/forest", "forest", "T", [("T", 0.1), ("Y", 0.04)], ",", ["herb_rare"], "lightning",
     [("air_elemental", "Lôi Linh"), ("griffon", "Sư Ưng Sấm"), ("harpy", "Điểu Nữ Lôi Phong")],
     ("storm_dragon", "Lôi Long Phong Bạo"), "hue-rotate(40deg) saturate(1.8) brightness(1.1)"),
    ("Đầm Lầy Thực Thi", "floors/swamp", "swamp", "T", [("~", 0.14), ("K", 0.05)], ",", ["herb", "herb_rare"], "earth",
     [("bog_body", "Xác Đầm Thực Thi"), ("swamp_worm", "Giun Đầm Khổng Lồ"), ("basilisk", "Xà Vương Hóa Đá")],
     ("swamp_dragon", "Long Đầm Thực Thi"), "hue-rotate(60deg) saturate(1.4) brightness(0.9)"),
    ("Cao Nguyên Gió Hú", "floors/mountain", "mountain", "R", [("R", 0.12), ("Y", 0.03)], ":", ["ore", "ore_rare"], "wind",
     [("wyvern", "Dực Long Gió Hú"), ("manticore", "Sư Nhân Gió"), ("cyclops", "Độc Nhãn Cao Nguyên")],
     ("hydra5", "Cửu Đầu Xà Bão Tố"), "hue-rotate(110deg) saturate(1.3) brightness(1.1)"),
    ("Thánh Địa Hoàng Kim", "floors/camp", "camp", "#", [("I", 0.05), ("R", 0.05)], ":", ["ore_rare"], "light",
     [("crystal_guardian", "Vệ Binh Pha Lê"), ("iron_golem", "Người Sắt Thánh Địa"), ("titan", "Titan Hoàng Kim")],
     ("golden_dragon", "Kim Long Thánh Địa"), "sepia(0.6) saturate(2) hue-rotate(-10deg) brightness(1.2)"),
    ("Vực Hư Không", "floors/graveyard", "graveyard", "K", [("K", 0.1), ("S", 0.05)], ":", ["herb_rare"], "dark",
     [("phantom", "U Hồn Hư Không"), ("wight", "Thi Ma Hư Không"), ("revenant", "Oan Hồn Báo Thù")],
     ("shadow_dragon", "Ám Long Hư Không"), "hue-rotate(250deg) saturate(1.5) brightness(0.85)"),
    ("Núi Lửa Diệt Thế", "floors/lair", "lair", "#", [("~", 0.12), ("I", 0.05)], "", ["ore_rare", "herb_rare"], "fire",
     [("fire_giant", "Hỏa Nhân Diệt Thế"), ("quicksilver_dragon", "Thủy Ngân Long"), ("ettin", "Song Đầu Dung Nham")],
     ("ancient_dragon", "Cổ Long Diệt Thế"), "hue-rotate(-30deg) saturate(2) contrast(1.15)"),
    ("Mộ Địa Thần Ma", "floors/graveyard", "graveyard", "#", [("I", 0.06), ("S", 0.06)], "", ["ore_rare"], "dark",
     [("death_knight", "Kỵ Sĩ Thần Ma"), ("vampire", "Huyết Tộc Cổ"), ("reaper", "Tử Thần Mộ Địa")],
     ("bone_dragon", "Cốt Long Thần Ma"), "hue-rotate(300deg) saturate(1.6) brightness(0.9)"),
    ("Thiên Giới Hỗn Mang", "floors/lair", "lair", "R", [("R", 0.08), ("~", 0.08)], ":", ["ore_rare", "herb_rare"], "light",
     [("white_wizard", "Pháp Sư Thiên Giới"), ("lich", "Vu Yêu Hỗn Mang"), ("stone_giant", "Thạch Thần")],
     ("ancient_lich", "Hỗn Mang Chi Chủ"), "invert(0.15) hue-rotate(200deg) saturate(1.8) brightness(1.15)"),
]


def rid(k, n=1):
    return "realm_%02d" % k if n == 1 else "realm_%02d_%d" % (k, n)


def bfs(grid, start):
    seen, q = {start}, deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H and (nx, ny) not in seen and grid[ny][nx] in WALK:
                seen.add((nx, ny))
                q.append((nx, ny))
    return seen


def make_map(k, r, mons, n, last):
    """Bản đồ thứ n (1…last) của vùng k; `mons`: 3 quái thường (+ chúa tể nếu là bản đồ cuối)."""
    name, floor, theme, wall, obst, deco, gather = r[:7]
    rnd = random.Random(6000 + k if n == 1 else 6000 + 100 * n + k)
    grid = [[wall if x in (0, W - 1) or y in (0, H - 1) else "." for x in range(W)] for y in range(H)]
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            v, acc = rnd.random(), 0
            for ch, p in obst:
                acc += p
                if v < acc:
                    grid[y][x] = ch
                    break
            else:
                if deco and rnd.random() < 0.16:
                    grid[y][x] = rnd.choice(deco)
    y = MID
    for x in range(1, W - 1):
        grid[y][x] = ":" if deco else "."
        if 3 < x < W - 3 and rnd.random() < 0.3:
            ny = max(3, min(H - 4, y + rnd.choice((-1, 1))))
            grid[ny][x] = grid[y][x]
            y = ny
    for yy in range(min(y, MID), max(y, MID) + 1):
        grid[yy][W - 2] = ":" if deco else "."
    for dx in (1, 2, 3):
        grid[MID][dx] = "."
        grid[MID][W - 1 - dx] = "."
    if n == 1:
        # Đài Phúc Lành gần cổng vào, chỗ đứng ngay dưới
        grid[MID - 2][3] = "W"
        grid[MID - 1][3] = "."
        portals = [{"at": [0, MID], "to": rid(k - 1) if k > 1 else "village",
                    "spawn": [W - 2, MID] if k > 1 else None}]
        if k < len(REALMS):
            grid[MID][W - 1] = "O"
            portals.append({"at": [W - 1, MID], "to": rid(k + 1), "spawn": [1, MID]})
        if last > 1:
            # nhánh sâu: cổng mép dưới giữa bản đồ, lối đi thẳng xuống từ đường chính
            for yy in range(MID, H - 1):
                grid[yy][DOWN] = ":" if deco else "."
            grid[H - 1][DOWN] = "O"
            portals.append({"at": [DOWN, H - 1], "to": rid(k, 2), "spawn": [1, MID]})
    else:
        portals = [{"at": [0, MID], "to": rid(k, n - 1), "spawn": [DOWN, H - 2] if n == 2 else [W - 2, MID]}]
        if n < last:
            grid[MID][W - 1] = "O"
            portals.append({"at": [W - 1, MID], "to": rid(k, n + 1), "spawn": [1, MID]})
    grid[MID][0] = "O"
    ok = bfs(grid, (1, MID))
    for yy in range(1, H - 1):
        for xx in range(1, W - 1):
            if grid[yy][xx] in WALK and (xx, yy) not in ok and grid[yy][xx] != "W":
                grid[yy][xx] = obst[0][0]
    spawns = [{"monster": m["id"], "max": 4, "respawn": 25} for m in mons[:3]]
    if len(mons) > 3:
        spawns.append({"monster": mons[3]["id"], "max": 1, "respawn": 240})
    m = {
        "id": rid(k, n), "name": name if n == 1 else f"{name} {n}", "zone": None, "side": True, "theme": theme,
        "floor": floor, "realm": k, "min_rebirths": k, "min_level": RULES["min_level"],
        "tiles": ["".join(r) for r in grid], "portals": portals, "spawns": spawns,
        "gather": [{"item": it, "max": 2, "respawn": 60} for it in gather], "npcs": [],
    }
    if n == 1:
        m["waystone"] = {"at": [3, MID - 2], "spawn": [3, MID - 1]}
    return m


def depth_tint(n):
    """Bản đồ càng sâu hình quái càng tối, đậm màu hơn chút (cùng hình gốc)."""
    return "" if n == 1 else " brightness(%s) saturate(%s)" % (round(1 - 0.06 * (n - 1), 2), round(1 + 0.12 * (n - 1), 2))


def add_parent_portal(parent_id, to, spawn_in):
    """Cổng `O` ở mép trái bản đồ cha dẫn vào vùng (như gen_side_maps.py), trả về ô đứng khi quay về."""
    path = os.path.join(MAPS, parent_id + ".json")
    m = json.load(open(path, encoding="utf-8"))
    rows = [list(r) for r in m["tiles"]]
    h = len(rows)
    for p in m["portals"]:
        if p["to"] == to:
            return [p["at"][0] + 1, p["at"][1]]
    taken = {tuple(p["at"]) for p in m["portals"]}
    npcs = {tuple(n["at"]) for n in m.get("npcs", [])}
    for y in sorted(range(1, h - 1), key=lambda y: abs(y - h // 2)):
        x = 0
        if (x, y) in taken or rows[y][x + 1] not in WALK or (x + 1, y) in npcs:
            continue
        if any(abs(y - ty) < 3 and tx == x for tx, ty in taken):
            continue
        rows[y][x] = "O"
        m["tiles"] = ["".join(r) for r in rows]
        m["portals"].append({"at": [x, y], "to": to, "spawn": spawn_in})
        with open(path, "w", encoding="utf-8") as f:
            json.dump(m, f, ensure_ascii=False, indent=2)
            f.write("\n")
        return [x + 1, y]
    raise SystemExit(f"không chỗ đặt cổng ở {parent_id}")


def main():
    monsters, tints = [], []
    last = RULES["maps_per_realm"]
    step = RULES["depth_step"]
    for k, r in enumerate(REALMS, 1):
        el, kinds, boss, flt = r[7], r[8], r[9], r[10]
        top = 50 + 10 * k
        for n in range(1, last + 1):
            d = n - 1
            # bản đồ thứ n đánh như vùng ke = k + depth_step × (n − 1) (nội suy tới vùng k + 1)
            ke = round(k + step * d, 3) if d else k
            mult = round(1 + RULES["mult_per_realm"] * ke, 3)
            # công nhân riêng (nhẹ hơn máu) để phòng thủ người chơi còn ý nghĩa ở vùng cao (DECISIONS "Cân bằng cuối game")
            atk = round(1 + RULES["atk_mult_per_realm"] * ke, 3)
            xpm = round(1 + RULES["xp_mult_per_realm"] * ke, 3)
            up = round(10 * step * d)
            mons = []
            for j, (base, nm) in enumerate(kinds):
                mons.append({"id": f"r{k}_{base}" + ("" if n == 1 else f"_{n}"), "name": nm,
                             "level": top - 8 + 3 * j + up, "stat_level": RULES["stat_level"],
                             "mult": mult, "atk_mult": atk, "xp_mult": xpm, "element": el, "rich": ke,
                             "jewel_chance": round(RULES["jewel_base"] + RULES["jewel_per_realm"] * ke, 4)})
                if n > 1:
                    mons[-1]["depth"] = n
            tints += [[f"monsters/{b}", f"monsters/{m['id']}", flt + depth_tint(n)] for (b, _), m in zip(kinds, mons)]
            if n == last:
                # chúa tể: sức vùng k (không theo bản đồ), đứng ở bản đồ cuối của vùng
                mult, atk, xpm = (round(1 + RULES[f] * k, 3) for f in ("mult_per_realm", "atk_mult_per_realm", "xp_mult_per_realm"))
                mons.append({"id": f"r{k}_{boss[0]}", "name": boss[1], "level": top, "stat_level": RULES["stat_level"],
                             "mult": round(mult * RULES["boss_mult"], 3), "atk_mult": round(atk * RULES["boss_mult"], 3), "xp_mult": round(xpm * RULES["boss_mult"], 3), "element": el, "rich": k + 2,
                             "jewel_chance": round((RULES["jewel_base"] + RULES["jewel_per_realm"] * k) * 5, 4), "lord": True})
                tints.append([f"monsters/{boss[0]}", f"monsters/{mons[-1]['id']}", flt])
            monsters += mons
            m = make_map(k, r, mons, n, last)
            if k == 1 and n == 1:
                m["portals"][0]["spawn"] = add_parent_portal("village", rid(1), [1, MID])
            with open(os.path.join(MAPS, rid(k, n) + ".json"), "w", encoding="utf-8") as f:
                json.dump(m, f, ensure_ascii=False, indent=2)
                f.write("\n")
    for m in monsters:
        m.update({"sourceType": "DESIGN", "version": 1, "verified": False})
    # sinh bởi scripts/gen_realms.py (Phase 6, B-30): sửa số ở RULES.realms rồi chạy lại
    out = {"REALM_MONSTERS": monsters, "REALM_TINTS": tints}
    with open(os.path.join(ROOT, "priv/game_data/realms.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(len(REALMS), "vùng ×", last, "bản đồ,", len(monsters), "quái")


main()

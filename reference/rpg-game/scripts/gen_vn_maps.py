"""Bản đồ mang chất Việt (DECISIONS "Bản đồ đẹp hơn": B1 bản đồ mới, B3 bản đồ lớn, B2 bản đồ bí mật).

Sinh 7 bản đồ phụ `priv/maps/vn_*.json`, thêm quái của chúng vào `SIDE_MONSTERS` (priv/game_data/side.json, mỗi
loại id `vn_…`, chỉ số tính theo cấp như quái bản đồ phụ khác) và danh sách tô màu hình `VN_TINTS` (hình quái tô lại
từ hình CC0 có sẵn bằng `node e2e/tint_sprites.mjs`), rồi gắn cổng vào bản đồ cha (ô `O` ở mép phải).

- Làng Chài Ven Biển (cấp 8–10, câu cá biển) → Chợ Nổi (không quái, câu cá).
- Rừng Tre (14–16): ô cây vẽ thành bụi tre (`style: "bamboo"`).
- Ruộng Bậc Thang (20–24) và Đồng Bằng Sông Nước (26–30): bản đồ lớn 50 × 35.
- Đền Cổ Trên Núi (34–38) → cổng ẩn tới Động Bí Ẩn (40–44, `secret: "night"`: chỉ vào được ban đêm, nhiều quặng /
  thảo dược quý hơn; không có trong Thư viện, Chọn map).

Ngẫu nhiên có hạt giống cố định (chạy lại ra y hệt). Ô đi được không tới được từ cổng vào bị lấp.
Chạy: python3 scripts/gen_vn_maps.py && node e2e/tint_sprites.mjs vn_
"""
import json, os, random
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPS = os.path.join(ROOT, "priv/maps")
SIDE = os.path.join(ROOT, "priv/game_data/side.json")
WALK = set(".,:*DAO><BE")

# (id, tên, cấp, hình gốc, bộ lọc canvas)
MONSTERS = {
    "vn_lang_chai": [
        ("vn_cua_da", "Cua Đá", 8, "scorpion", "hue-rotate(-30deg) saturate(1.8) brightness(1.05)"),
        ("vn_ran_bien", "Rắn Biển", 9, "water_moccasin", "hue-rotate(160deg) saturate(1.3)"),
        ("vn_thuy_quai_con", "Thủy Quái Con", 10, "giant_newt", "hue-rotate(120deg) saturate(1.4)"),
    ],
    "vn_rung_tre": [
        ("vn_ma_rung_tre", "Ma Rừng Tre", 14, "ghost", "sepia(0.5) hue-rotate(60deg) saturate(2.2)"),
        ("vn_ho_xam", "Hổ Xám", 15, "wolf", "sepia(0.6) saturate(1.6) hue-rotate(-15deg)"),
        ("vn_ran_ho_mang", "Rắn Hổ Mang", 16, "adder", "brightness(0.7) saturate(1.6)"),
    ],
    "vn_ruong_bac_thang": [
        ("vn_chuot_dong", "Chuột Đồng Khổng Lồ", 20, "quokka", "sepia(0.8) brightness(0.8)"),
        ("vn_chau_chau", "Châu Chấu Khổng Lồ", 21, "yellow_wasp", "hue-rotate(60deg) saturate(1.5)"),
        ("vn_trau_dien", "Trâu Điên", 22, "wild_yak", "brightness(0.6) contrast(1.3)"),
        ("vn_bu_nhin", "Bù Nhìn Ma", 23, "thorn_hunter", "sepia(1) saturate(1.5)"),
        ("vn_co_ma", "Cò Ma Đồng", 24, "harpy", "grayscale(1) brightness(1.4)"),
    ],
    "vn_dong_bang": [
        ("vn_ca_sau", "Cá Sấu Đầm", 26, "iguana", "hue-rotate(40deg) brightness(0.75)"),
        ("vn_dia_trau", "Đỉa Trâu", 27, "giant_leech", "hue-rotate(-40deg) saturate(1.6)"),
        ("vn_rua_da", "Rùa Đá Khổng Lồ", 28, "basilisk", "grayscale(0.7) sepia(0.4)"),
        ("vn_thuy_binh", "Thủy Binh", 29, "water_elemental", "hue-rotate(30deg) saturate(1.5)"),
        ("vn_ha_ba", "Hà Bá", 30, "swamp_dragon", "hue-rotate(150deg) saturate(1.2)"),
    ],
    "vn_den_co": [
        ("vn_thach_su", "Thạch Sư Gác Đền", 34, "manticore", "grayscale(0.9) brightness(1.1)"),
        ("vn_hon_tuong", "Hồn Tướng Cổ", 35, "skeletal_warrior", "sepia(1) saturate(2.5) hue-rotate(-10deg)"),
        ("vn_hau_vuong", "Hầu Vương Đá", 36, "ogre", "grayscale(0.8) brightness(0.95)"),
        ("vn_rong_da", "Rồng Đá Đền", 37, "wyvern", "grayscale(1) brightness(1.05)"),
        ("vn_dao_si", "Đạo Sĩ Tà", 38, "lich", "hue-rotate(200deg) saturate(1.4)"),
    ],
    "vn_dong_bi_an": [
        ("vn_tinh_linh_dong", "Tinh Linh Động", 40, "air_elemental", "hue-rotate(220deg) saturate(2)"),
        ("vn_nhen_ngoc", "Nhện Ngọc", 41, "spider", "hue-rotate(150deg) saturate(2) brightness(1.2)"),
        ("vn_doi_ma", "Dơi Ma Tím", 42, "bat", "hue-rotate(250deg) saturate(2)"),
        ("vn_nguoi_da", "Người Đá Tinh Thể", 43, "crystal_guardian", "hue-rotate(90deg) saturate(1.6)"),
        ("vn_thach_long", "Thạch Long Ẩn", 44, "quicksilver_dragon", "hue-rotate(260deg) saturate(1.5)"),
    ],
}


def bfs(grid, start):
    h, w = len(grid), len(grid[0])
    seen = {start}
    q = deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and grid[ny][nx] in WALK:
                seen.add((nx, ny))
                q.append((nx, ny))
    return seen


def blank(w, h, wall, floor="."):
    return [[wall if x in (0, w - 1) or y in (0, h - 1) else floor for x in range(w)] for y in range(h)]


def scatter(grid, rnd, items, y0=1, y1=None, x0=1, x1=None):
    h, w = len(grid), len(grid[0])
    for y in range(y0, (y1 or h - 1)):
        for x in range(x0, (x1 or w - 1)):
            if grid[y][x] != ".":
                continue
            r, acc = rnd.random(), 0
            for ch, p in items:
                acc += p
                if r < acc:
                    grid[y][x] = ch
                    break


def road(grid, rnd, y, x0, x1, ch=":", wiggle=0.3, ymin=2, ymax=None):
    h = len(grid)
    ymax = ymax or h - 3
    for x in range(x0, x1 + 1):
        grid[y][x] = ch
        if x0 + 2 < x < x1 - 2 and rnd.random() < wiggle:
            ny = max(ymin, min(ymax, y + rnd.choice((-1, 1))))
            grid[ny][x] = ch
            y = ny
    return y


def finish(grid, start, fill):
    ok = bfs(grid, start)
    for y in range(1, len(grid) - 1):
        for x in range(1, len(grid[0]) - 1):
            if grid[y][x] in WALK and (x, y) not in ok:
                grid[y][x] = fill


def house(grid, x, y, w=3, h=2):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            grid[yy][xx] = "#"


# ---------- từng bản đồ ----------

def lang_chai():
    W, H, mid = 30, 20, 7
    rnd = random.Random(8101)
    g = blank(W, H, "T", ",")
    for y in range(13, H - 1):
        for x in range(1, W - 1):
            g[y][x] = "~"
    for x in range(1, W - 1):
        g[12][x] = ":" if rnd.random() < 0.7 else "."
    for px in (6, 15, 24):
        for y in range(13, 17):
            g[y][px] = "B"
        g[17][px] = "U"
    for bx in (3, 11, 20, 27):
        g[15][bx] = "U"
    for hx in (3, 10, 19):
        house(g, hx, 3)
    for lx in (8, 17, 26):
        g[11][lx] = "J"
    scatter(g, rnd, [("Y", 0.04), ("T", 0.03), ("*", 0.05)], y0=1, y1=11)
    road(g, rnd, mid, 1, W - 2, wiggle=0.25, ymin=6, ymax=10)
    g[mid][0] = "O"
    g[mid][W - 1] = "O"
    for y in range(6, 12):
        g[y][W - 2] = ":"
    finish(g, (1, mid), "T")
    return g, [[0, mid], [W - 1, mid]], [
        {"id": "boat_lady", "name": "Bà Chủ Thuyền", "sprite": "girl", "at": [13, 11], "role": "talk",
         "lines": ["Biển hôm nay động, cẩn thận lũ Cua Đá trên bờ.", "Đi hết bờ biển về phía đông là tới Chợ Nổi đó cháu."]}]


def cho_noi():
    W, H, mid = 30, 20, 9
    rnd = random.Random(8102)
    g = blank(W, H, "~", "~")
    for x in range(1, W - 1):
        g[mid][x] = "E"
    for cx in (6, 14, 22):
        for y in range(3, H - 3):
            g[y][cx] = "B"
    for y in (4, 15):
        for x in range(4, W - 4):
            g[y][x] = "E"
    for (x, y) in [(3, 3), (9, 6), (18, 6), (25, 12), (10, 13), (17, 16), (27, 5), (4, 16)]:
        g[y][x] = "U"
    for (x, y) in [(7, 8), (13, 8), (21, 8), (8, 10), (15, 10), (23, 10)]:
        g[y][x] = "J"
    for (x, y) in [(2, 7), (12, 2), (26, 17), (19, 12)]:
        g[y][x] = "Q"
    g[mid][0] = "O"
    finish(g, (1, mid), "~")
    return g, [[0, mid]], [
        {"id": "fruit_seller", "name": "Cô Bán Trái Cây", "sprite": "merchant", "at": [10, 8], "role": "talk",
         "lines": ["Xoài, chôm chôm, sầu riêng đây! Đi xuồng cả buổi mới ra tới chợ đó.", "Đêm chợ thắp đèn lồng, đẹp lắm."]},
        {"id": "ferryman", "name": "Ông Lái Đò", "sprite": "fisher", "at": [18, 10], "role": "talk",
         "lines": ["Câu cá ở đây ra cá to như ở vùng sâu.", "Ngồi bến này câu thì nhớ để ý phao."]},
        {"id": "trader", "name": "Thương Nhân Phương Xa", "sprite": "dealer", "at": [21, 8], "role": "trader",
         "lines": ["Hàng hiếm từ khắp nơi, mỗi ngày một khác. Mua nhanh kẻo hết!"]}]


def rung_tre():
    W, H, mid = 30, 20, 10
    rnd = random.Random(8103)
    g = blank(W, H, "T")
    scatter(g, rnd, [("T", 0.24), ("~", 0.03), ("R", 0.02)])
    road(g, rnd, mid, 1, W - 2, wiggle=0.35)
    g[mid][0] = "O"
    finish(g, (1, mid), "T")
    return g, [[0, mid]], []


def ruong_bac_thang():
    W, H, mid = 50, 35, 17
    rnd = random.Random(8104)
    g = blank(W, H, "T", ",")
    # bậc ruộng: dải nước 2 hàng (lúa) xen dải bờ cỏ 3 hàng, bờ đất ở mép
    y = 3
    while y < H - 4:
        for yy in (y, y + 1):
            for x in range(2, W - 2):
                g[yy][x] = "~"
        for x in range(2, W - 2):
            if rnd.random() < 0.5:
                g[y + 2][x] = ":"
        y += 5
    # đường lên xuống cắt ngang các bậc
    for px in (6, 17, 28, 39, 46):
        for yy in range(1, H - 1):
            g[yy][px] = ":"
    scatter(g, rnd, [("Y", 0.03), ("T", 0.02), ("*", 0.04)])
    road(g, rnd, mid, 1, 7, wiggle=0)
    g[mid][0] = "O"
    finish(g, (1, mid), "T")
    return g, [[0, mid]], [
        {"id": "farmer", "name": "Bác Nông Dân", "sprite": "carpenter", "at": [8, 18], "role": "talk",
         "lines": ["Mùa này lúa chín vàng cả đồi.", "Lũ Châu Chấu Khổng Lồ phá ruộng, cháu đuổi giùm bác."]}]


def dong_bang():
    W, H, mid = 50, 35, 8
    rnd = random.Random(8105)
    g = blank(W, H, "T")
    scatter(g, rnd, [("M", 0.04), ("T", 0.05), ("Y", 0.02)])
    # sông uốn lượn ngang bản đồ, rộng 3 ô, có cầu gỗ
    y = 20
    for x in range(1, W - 1):
        for k in (-1, 0, 1):
            g[y + k][x] = "~"
        if rnd.random() < 0.25:
            y = max(14, min(H - 6, y + rnd.choice((-1, 1))))
    for x in range(1, W - 1):
        for yy in range(1, H - 1):
            if g[yy][x] == "~" and rnd.random() < 0.06:
                g[yy][x] = rnd.choice("QU")
    for bx in (8, 21, 34, 45):
        for yy in range(1, H - 1):
            if g[yy][bx] in "~QU":
                g[yy][bx] = "B"
    # đường đất dọc mỗi cầu + đường ngang phía trên
    road(g, rnd, mid, 1, W - 2, wiggle=0.2, ymin=4, ymax=10)
    for bx in (8, 21, 34, 45):
        for yy in range(2, H - 2):
            if g[yy][bx] not in "B":
                g[yy][bx] = ":"
    g[mid][0] = "O"
    finish(g, (1, mid), "T")
    return g, [[0, mid]], [
        {"id": "boatman", "name": "Chú Chèo Xuồng", "sprite": "fisher", "at": [9, 9], "role": "talk",
         "lines": ["Sông này nhiều Hà Bá lắm, đi cầu cho chắc.", "Ven sông câu cá cũng được đó."]}]


def den_co():
    W, H, mid = 30, 20, 12
    rnd = random.Random(8106)
    g = blank(W, H, "R")
    scatter(g, rnd, [("R", 0.1), ("Y", 0.02)])
    # sân đền: tường đá bao quanh, cột hai hàng, tượng rồng, đèn lồng
    for x in range(8, 22):
        g[3][x] = "S"
    for y in range(3, 9):
        g[y][8] = "S"
        g[y][21] = "S"
    for x in range(9, 21):
        for y in range(4, 9):
            g[y][x] = "."
    for x in (10, 13, 16, 19):
        g[5][x] = "I"
        g[7][x] = "I"
    g[4][11], g[4][18] = "G", "G"
    g[8][12], g[8][17] = "J", "J"
    for y in range(8, H - 1):
        g[y][14] = ":"
        g[y][15] = ":"
    g[8][14] = g[8][15] = "."
    road(g, rnd, mid, 1, W - 2, wiggle=0.2, ymin=10, ymax=16)
    # cổng ẩn tới Động Bí Ẩn: chính giữa bức tường sau đền
    g[3][14] = "O"
    g[4][14] = "."
    g[mid][0] = "O"
    finish(g, (1, mid), "R")
    return g, [[0, mid], [14, 3]], [
        {"id": "monk", "name": "Lão Từ Giữ Đền", "sprite": "elder", "at": [16, 9], "role": "talk",
         "lines": ["Lão giữ ngôi đền này đã sáu mươi năm.", "Đêm nào đá trong núi rung, đêm ấy khe đá sau đền mở ra."]},
        {"id": "secret_board", "name": "Bia Động Bí Ẩn", "sprite": "board", "at": [11, 9], "role": "secret_board",
         "lines": ["Tên khắc trên bia: những người đã tìm ra động và hạ Thạch Long Ẩn."]}]


def dong_bi_an():
    W, H, mid = 30, 20, 16
    rnd = random.Random(8107)
    g = blank(W, H, "R")
    scatter(g, rnd, [("R", 0.13), ("~", 0.06), ("I", 0.02)])
    road(g, rnd, mid, 1, W - 2, wiggle=0.4, ymin=3, ymax=16)
    g[H - 1][14] = "O"
    for y in range(mid, H - 1):
        g[y][14] = ":"
    finish(g, (14, H - 2), "R")
    return g, [[14, H - 1]], []


# Trùm đêm Động Bí Ẩn (DECISIONS "Động Bí Ẩn"): không sinh theo `spawns`, HacLong.World.Secret thả mỗi đêm động mở;
# `hidden`: không có trong Thư viện. Chỉ số ×`mult`, chắc chắn rơi ngọc (`jewel_chance` 1).
NIGHT_BOSS = ("vn_thach_long_than", "Thạch Long Ẩn", 46, "ancient_dragon", "hue-rotate(250deg) saturate(1.6) brightness(0.9)",
              {"mult": 1.4, "jewel_chance": 1.0, "hidden": True})

# (id, tên, hàm, nền, nền trận, cha, cổng phụ, thêm)
SPECS = [
    ("vn_lang_chai", "Làng Chài Ven Biển", lang_chai, "tiles/grass", "forest", "camp_1",
     {"fish": "deep", "gather": [("herb", 2, 70)]}),
    ("vn_cho_noi", "Chợ Nổi", cho_noi, "tiles/grass", "forest", None,
     {"fish": "deep", "min_level": 8}),
    ("vn_rung_tre", "Rừng Tre", rung_tre, "floors/forest", "forest", "graveyard_1",
     {"style": "bamboo", "gather": [("herb", 3, 60)]}),
    ("vn_ruong_bac_thang", "Ruộng Bậc Thang", ruong_bac_thang, "floors/forest", "forest", "mountain_1",
     {"style": "paddy", "max": 7, "gather": [("herb", 4, 60)]}),
    ("vn_dong_bang", "Đồng Bằng Sông Nước", dong_bang, "floors/swamp", "swamp", "swamp_1",
     {"max": 7, "fish": "deep", "gather": [("herb", 3, 60), ("herb_rare", 2, 80)]}),
    ("vn_den_co", "Đền Cổ Trên Núi", den_co, "floors/mountain", "mountain", "lair_2",
     {"style": "temple", "gather": [("ore_rare", 2, 70)]}),
    ("vn_dong_bi_an", "Động Bí Ẩn", dong_bi_an, "floors/lair", "lair", None,
     {"secret": "night", "min_level": 38, "gather": [("ore_rare", 4, 45), ("herb_rare", 4, 45)]}),
]


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


def inside(at, w, h):
    """Ô đứng ngay trong cổng `at` (mép trái → x+1, mép phải → x-1, mép trên → y+1, mép dưới → y-1)."""
    x, y = at
    if x == 0:
        return [1, y]
    if x == w - 1:
        return [w - 2, y]
    if y == 0:
        return [x, 1]
    if y == h - 1:
        return [x, h - 2]
    return [x, y + 1]


def main():
    side = json.load(open(SIDE, encoding="utf-8"))
    side["SIDE_MONSTERS"] = [m for m in side["SIDE_MONSTERS"] if not m["id"].startswith("vn_")]
    tints = []
    for mons in MONSTERS.values():
        for mid, name, lv, src, flt in mons:
            side["SIDE_MONSTERS"].append({"id": mid, "name": name, "level": lv})
            tints.append([f"monsters/{src}", f"monsters/{mid}", flt])
    bid, bname, blv, bsrc, bflt, bextra = NIGHT_BOSS
    side["SIDE_MONSTERS"].append({"id": bid, "name": bname, "level": blv, **bextra})
    tints.append([f"monsters/{bsrc}", f"monsters/{bid}", bflt])
    side["VN_TINTS"] = tints
    with open(SIDE, "w", encoding="utf-8") as f:
        json.dump(side, f, ensure_ascii=False, indent=1)
        f.write("\n")

    built = {}
    for mid, name, fn, floor, theme, parent, extra in SPECS:
        grid, gates, npcs = fn()
        # NPC đứng trên ô đi được: trên nước thì đặt một tấm ván (cầu gỗ), trên đất thì nền thường
        for n in npcs:
            x, y = n["at"]
            if grid[y][x] not in WALK:
                grid[y][x] = "E" if grid[y][x] in "~QU" else "."
        built[mid] = (name, grid, gates, npcs, floor, theme, parent, extra)

    # cổng: cổng đầu tiên của mỗi bản đồ về cha; Làng Chài → Chợ Nổi; Đền Cổ (cổng thứ hai) → Động Bí Ẩn
    links = {"vn_lang_chai": {1: "vn_cho_noi"}, "vn_den_co": {1: "vn_dong_bi_an"}}
    back = {"vn_cho_noi": ("vn_lang_chai", 1), "vn_dong_bi_an": ("vn_den_co", 1)}
    out = {}
    for mid, (name, grid, gates, npcs, floor, theme, parent, extra) in built.items():
        h, w = len(grid), len(grid[0])
        portals = []
        for i, at in enumerate(gates):
            if i == 0 and parent:
                spawn = add_parent_portal(parent, mid, inside(at, w, h))
                portals.append({"at": at, "to": parent, "spawn": spawn})
            elif i == 0 and mid in back:
                src, gi = back[mid]
                sname, sgrid, sgates = built[src][0], built[src][1], built[src][2]
                portals.append({"at": at, "to": src, "spawn": inside(sgates[gi], len(sgrid[0]), len(sgrid))})
            else:
                to = links[mid][i]
                tgrid, tgates = built[to][1], built[to][2]
                portals.append({"at": at, "to": to, "spawn": inside(tgates[0], len(tgrid[0]), len(tgrid))})
        mons = MONSTERS.get(mid, [])
        m = {
            "id": mid,
            "name": name,
            "zone": None,
            "side": True,
            "theme": theme,
            "floor": floor,
            "tiles": ["".join(r) for r in grid],
            "portals": portals,
            "spawns": [{"monster": x[0], "max": extra.get("max", 4), "respawn": 25} for x in mons],
            "gather": [{"item": it, "max": n, "respawn": r} for it, n, r in extra.get("gather", [])],
            "npcs": npcs,
            "sourceType": "DESIGN",
            "version": 1,
            "verified": False,
        }
        for k in ("fish", "style", "secret", "min_level"):
            if k in extra:
                m[k] = extra[k]
        out[mid] = m
    for mid, m in out.items():
        with open(os.path.join(MAPS, mid + ".json"), "w", encoding="utf-8") as f:
            json.dump(m, f, ensure_ascii=False, indent=2)
            f.write("\n")
    print(len(out), "bản đồ,", len(tints), "quái")


main()

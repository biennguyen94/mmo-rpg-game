"""Phase 7 (B-33): bộ hình đồ "Pixel" thay cho hình MU, lấy từ Dungeon Crawl Stone Soup tiles (CC0,
https://github.com/crawl/tiles, releases/Nov-2015).

Chạy:  python3 scripts/pixel_icons.py <thư_mục releases/Nov-2015 của crawl/tiles>

Hình quần không có trong bộ tile trên: lấy từ "CC0 Leggings Icons" (CC0, có sẵn trong repo ở
assets_src/pixel_extra/leggings/, nguồn ghi trong SOURCES.md); trong RULES viết là "extra:leggings/<tên>".
Hình cánh: đôi cánh Draconian của bộ tile trên (player/drcwing), đã ghép sát hai cánh và căn giữa sẵn ở
assets_src/pixel_extra/wings/
("extra:wings/<màu>").

Ghi priv/static/assets/pixel/*.png (chỉ những hình được dùng) và priv/static/assets/pixel_icons.json
(mã món → đường dẫn hình). Mỗi loại đồ có một dãy hình xếp từ yếu tới mạnh; món trong loại xếp theo cấp rồi
chia đều lên dãy hình, nên đồ cấp cao trông "xịn" hơn. Bỏ mọi file có trong TILES_UNDER_UNKNOWN_LICENSE.md.
Không đụng tới hình MU (`mu_items/`, `item_icons.json`).
"""
import json, os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "priv/static/assets/pixel")
OUT_MAP = os.path.join(ROOT, "priv/static/assets/pixel_icons.json")
EXTRA_DIR = os.path.join(ROOT, "assets_src/pixel_extra")

# (điều kiện trên món, dãy hình từ yếu tới mạnh; đường dẫn trong releases/Nov-2015/)
W = "item/weapon/"
A = "item/armour/"
LEG = "extra:leggings/"
WING = "extra:wings/"
RULES = [
    # vũ khí (nhóm MU: 0 kiếm, 1 rìu, 2 chùy / quyền trượng, 3 giáo / lưỡi hái, 4 cung / nỏ, 5 gậy / sách)
    (lambda it, g, n: it["slot"] == "weapon" and g == "4" and re.search(r"crossbow|arquebus", n),
     [W + "ranged/hand_crossbow", W + "ranged/hand_crossbow2", W + "ranged/hand_crossbow3", W + "ranged/arbalest1",
      W + "ranged/arbalest2", W + "ranged/arbalest3"]),
    (lambda it, g, n: it["slot"] == "weapon" and g == "4",
     [W + "ranged/shortbow1", W + "ranged/shortbow2", W + "ranged/shortbow3", W + "ranged/longbow1",
      W + "ranged/longbow2", W + "ranged/longbow3"]),
    (lambda it, g, n: it["slot"] == "weapon" and g == "5" and "book" in n,
     ["item/book/leather", "item/book/dark_blue", "item/book/metal_cyan", "item/book/book_of_the_dead"]),
    (lambda it, g, n: it["slot"] == "weapon" and g == "5",
     ["item/staff/staff00", "item/staff/staff01", "item/staff/staff02", "item/staff/staff03", "item/staff/staff04",
      "item/staff/staff05", "item/staff/staff06", "item/staff/staff07", "item/staff/staff08", "item/staff/staff09"]),
    (lambda it, g, n: it["slot"] == "weapon" and g == "2" and "scepter" in n,
     ["item/rod/rod00", "item/rod/rod01", "item/rod/rod02", "item/rod/rod03", "item/rod/rod04", "item/rod/rod05",
      "item/rod/rod06", "item/rod/rod07", "item/rod/rod08", "item/rod/rod09"]),
    (lambda it, g, n: it["slot"] == "weapon" and g == "2" and "morning" in n,
     [W + "morningstar1", W + "morningstar2", W + "eveningstar1", W + "eveningstar2"]),
    (lambda it, g, n: it["slot"] == "weapon" and g == "2" and "flail" in n, [W + "flail1", W + "dire_flail1"]),
    (lambda it, g, n: it["slot"] == "weapon" and g == "2" and "hammer" in n, [W + "mace_large1", W + "mace_large3"]),
    (lambda it, g, n: it["slot"] == "weapon" and g == "2" and "axe" in n, [W + "hand_axe3"]),
    (lambda it, g, n: it["slot"] == "weapon" and g == "2" and "sword" in n, [W + "double_sword3"]),
    (lambda it, g, n: it["slot"] == "weapon" and g == "2", [W + "mace1", W + "mace2", W + "mace3"]),
    (lambda it, g, n: it["slot"] == "weapon" and g == "3" and "scythe" in n, [W + "scythe1", W + "scythe3"]),
    (lambda it, g, n: it["slot"] == "weapon" and g == "3",
     [W + "spear1", W + "spear2", W + "spear3", W + "trident1", W + "trident2", W + "trishula"]),
    (lambda it, g, n: it["slot"] == "weapon" and g == "1",
     [W + "hand_axe1", W + "hand_axe2", W + "war_axe1", W + "war_axe2", W + "hand_axe3", W + "war_axe3"]),
    (lambda it, g, n: it["slot"] == "weapon" and (g == "0" or it.get("icon") in ("broadsword", "two-handed-sword")),
     [W + "dagger", W + "short_sword1", W + "short_sword2", W + "rapier1", W + "rapier2", W + "falchion1",
      W + "falchion2", W + "scimitar1", W + "long_sword1", W + "long_sword3", W + "greatsword1", W + "greatsword3",
      W + "double_sword", W + "double_sword2", W + "triple_sword", W + "triple_sword2", W + "triple_sword3"]),
    (lambda it, g, n: it["slot"] == "weapon", [W + "club", W + "mace1", W + "mace2", W + "mace3"]),
    # khiên
    (lambda it, g, n: it["slot"] == "shield",
     [A + "shields/buckler1", A + "shields/buckler2", A + "shields/buckler3", A + "shields/shield1",
      A + "shields/shield2", A + "shields/shield3", A + "shields/large_shield1", A + "shields/large_shield2",
      A + "shields/large_shield3", A + "shields/shield_dd", A + "shields/lshield_dd_dk"]),
    # mũ: Pháp Sư đội nón, Tiên Nữ mũ da, còn lại mũ sắt
    (lambda it, g, n: it["slot"] == "helm" and it.get("classes") == ["dw"],
     [A + "headgear/hat1", A + "headgear/hat2", A + "headgear/hat3"]),
    (lambda it, g, n: it["slot"] == "helm" and it.get("classes") == ["elf"],
     [A + "headgear/elven_leather_helm", A + "headgear/helmet_ego1", A + "headgear/helmet_art1"]),
    (lambda it, g, n: it["slot"] == "helm",
     [A + "headgear/helmet1", A + "headgear/helmet2", A + "headgear/helmet3", A + "headgear/helmet4",
      A + "headgear/helmet5", A + "headgear/helmet_ego2", A + "headgear/helmet_ego3", A + "headgear/helmet_ego4",
      A + "headgear/helmet_art2", A + "headgear/helmet_art3"]),
    # giáp: Pháp Sư áo choàng, Tiên Nữ giáp da / vảy rồng, còn lại giáp xích → giáp tấm → giáp rồng
    (lambda it, g, n: it["slot"] == "armor" and it.get("classes") == ["dw"],
     [A + "robe1", A + "robe2", A + "robe_ego1", A + "robe_ego2", A + "robe_art1", A + "robe_art2"]),
    (lambda it, g, n: it["slot"] == "armor" and it.get("classes") == ["elf"],
     [A + "animal_skin1", A + "leather_armour1", A + "animal_skin2", A + "swamp_dragon_armour",
      A + "mottled_dragon_armour", A + "pearl_dragon_armour", A + "silver_dragon_scale_mail"]),
    (lambda it, g, n: it["slot"] == "armor",
     [A + "ring_mail1", A + "ring_mail2", A + "scale_mail1", A + "scale_mail2", A + "scale_mail3", A + "plate1",
      A + "ice_dragon_armour", A + "blue_dragon_scale_mail", A + "shadow_dragon_scale_mail", A + "gold_dragon_armour"]),
    # quần (CC0 Leggings Icons): Pháp Sư vải → áo choàng → quần lụa → giáp quỷ, Tiên Nữ da → lá rừng → giáp xanh,
    # còn lại vải → da → xích → giáp tấm → giáp thép → giáp quỷ
    (lambda it, g, n: it["slot"] == "pants" and it.get("classes") == ["dw"],
     [LEG + "cloth", LEG + "robe", LEG + "plate", LEG + "underworld"]),
    (lambda it, g, n: it["slot"] == "pants" and it.get("classes") == ["elf"],
     [LEG + "leather", LEG + "forest", LEG + "plate_green"]),
    (lambda it, g, n: it["slot"] == "pants",
     [LEG + "cloth", LEG + "leather", LEG + "chain", LEG + "plate", LEG + "medieval", LEG + "underworld"]),
    # cánh (bậc 1 → 3) theo lớp: Chiến Binh nâu → rồng đỏ → bão tím, Pháp Sư trắng → vàng → xanh nhạt,
    # Tiên Nữ lục → đốm → trắng, Đấu Sĩ xám → tím → đen
    (lambda it, g, n: it["slot"] == "wing" and it["id"].startswith("wing_dk_"),
     [WING + "brown", WING + "red", WING + "purple"]),
    (lambda it, g, n: it["slot"] == "wing" and it["id"].startswith("wing_dw_"),
     [WING + "white", WING + "yellow", WING + "pale"]),
    (lambda it, g, n: it["slot"] == "wing" and it["id"].startswith("wing_elf_"),
     [WING + "green", WING + "mottled", WING + "white"]),
    (lambda it, g, n: it["slot"] == "wing" and it["id"].startswith("wing_mg_"),
     [WING + "grey", WING + "purple", WING + "black"]),
    (lambda it, g, n: it["slot"] == "gloves",
     [A + "glove1", A + "glove2", A + "glove3", A + "glove4", A + "glove5"]),
    (lambda it, g, n: it["slot"] == "boots",
     [A + "boots1_brown", A + "boots3_stripe", A + "boots4_green", A + "boots2_jackboots"]),
    # nhẫn, dây chuyền: theo nguyên tố trong tên
    (lambda it, g, n: it["slot"] == "ring" and "ice" in n, ["item/ring/tourmaline"]),
    (lambda it, g, n: it["slot"] == "ring" and "fire" in n, ["item/ring/ruby"]),
    (lambda it, g, n: it["slot"] == "ring", ["item/amulet/ring_green", "item/amulet/ring_cyan", "item/amulet/ring_red"]),
    (lambda it, g, n: it["slot"] == "pendant" and "fire" in n, ["item/amulet/crystal_red"]),
    (lambda it, g, n: it["slot"] == "pendant" and "ice" in n, ["item/amulet/crystal_white"]),
    (lambda it, g, n: it["slot"] == "pendant" and "water" in n, ["item/amulet/stone2_blue"]),
    (lambda it, g, n: it["slot"] == "pendant", ["item/amulet/celtic_yellow", "item/amulet/stone3_green"]),
    # bình: máu đỏ, mana xanh, lớn dần
    (lambda it, g, n: it["slot"] == "potion" and it["id"].startswith("potion"),
     ["item/potion/ruby", "item/potion/purple_red", "item/potion/magenta"]),
    (lambda it, g, n: it["slot"] == "potion" and it["id"].startswith("mana"),
     ["item/potion/sky_blue", "item/potion/brilliant_blue", "item/potion/cyan"]),
]

# nguyên liệu, vé (theo mã)
BY_ID = {
    "jewel_bless": "item/misc/runes/rune_vaults",
    "jewel_soul": "item/misc/runes/rune_shoals",
    "jewel_chaos": "item/misc/runes/rune_abyss",
    "jewel_life": "item/misc/runes/rune_swamp",
    "ds_ticket": "item/scroll/scroll-red",
    "bc_ticket": "item/scroll/scroll-purple",
    "cc_ticket": "item/scroll/scroll-grey",
    "lost_map": "item/scroll/scroll-brown",
    "archangel_scroll": "item/scroll/scroll-yellow",
    "kundun_mark": "item/misc/misc_stone",
    "devil_eye": "item/amulet/eye_magenta",
    "devil_key": "item/misc/misc_box",
    "blood_bone": "item/amulet/bone_gray",
    "condor_feather": "item/misc/misc_fan",
}


def unknown_license(src):
    path = os.path.join(src, "..", "..", "TILES_UNDER_UNKNOWN_LICENSE.md")
    if not os.path.exists(path):
        path = os.path.join(src, "TILES_UNDER_UNKNOWN_LICENSE.md")
    with open(path, encoding="utf-8") as f:
        return {m.group(1) for m in re.finditer(r"rltiles/([\w/.-]+)\.png", f.read())}


def source(src, p):
    """Đường dẫn file hình: "extra:…" trong assets_src/pixel_extra, còn lại trong bộ tile."""
    return os.path.join(EXTRA_DIR, p[6:] + ".png") if p.startswith("extra:") else os.path.join(src, p + ".png")


def main(src):
    bad = unknown_license(src)
    ok = lambda p: os.path.exists(source(src, p)) and p not in bad
    items = {}
    for name, key in [("items.json", "ITEMS"), ("items_mu.json", "ITEMS_MU")]:
        with open(os.path.join(ROOT, "priv/game_data", name), encoding="utf-8") as f:
            for i, it in json.load(f)[key].items():
                items[i] = dict(it, id=i)

    # món → (luật, dãy hình còn dùng được)
    groups = {}
    for i, it in items.items():
        g = (it.get("ref") or "").split("/")[0]
        n = (it.get("mu_name") or it.get("name") or "").lower()
        for k, (cond, pool) in enumerate(RULES):
            if cond(it, g, n):
                groups.setdefault(k, []).append(it)
                break

    mapping = {}
    for k, its in groups.items():
        pool = [p for p in RULES[k][1] if ok(p)]
        if not pool:
            print(f"luật {k}: không còn hình dùng được", file=sys.stderr)
            continue
        its.sort(key=lambda it: (it.get("level") or 0, it.get("tier") or 0, it["id"]))
        for r, it in enumerate(its):
            j = round(r * (len(pool) - 1) / max(1, len(its) - 1))
            mapping[it["id"]] = pool[j]
    for i, p in BY_ID.items():
        if i in items and ok(p):
            mapping[i] = p

    if os.path.isdir(OUT_DIR):
        shutil.rmtree(OUT_DIR)
    os.makedirs(OUT_DIR)
    out = {}
    for i, p in sorted(mapping.items()):
        flat = p.replace("extra:", "").replace("item/", "").replace("/", "_")
        shutil.copyfile(source(src, p), os.path.join(OUT_DIR, flat + ".png"))
        out[i] = "pixel/" + flat + ".png"
    with open(OUT_MAP, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, sort_keys=True, indent=0)
    print(f"{len(out)} món, {len(set(out.values()))} hình → {OUT_DIR}")


if __name__ == "__main__":
    main(sys.argv[1])

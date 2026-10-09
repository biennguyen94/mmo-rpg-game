"""Phase 15a: 52 loài quái cho bản đồ phụ (cấp 1..52), hình lấy từ Dungeon Crawl Stone Soup tiles (CC0,
https://github.com/crawl/tiles, releases/Nov-2015). Chạy: python3 scripts/side_monsters.py <thư_mục_mon_của_crawl>
Ghi priv/game_data/side.json (SIDE_MONSTERS) và chép hình vào priv/static/assets/monsters/<id>.png."""
import json, shutil, sys, os

# (cấp, id, tên, đường dẫn trong mon/)
SPECIES = [
    (1, "quokka", "Chuột Túi Nhỏ", "animals/quokka"),
    (2, "wild_sheep", "Cừu Hoang", "animals/sheep"),
    (3, "wild_hog", "Heo Rừng", "animals/hog"),
    (4, "giant_newt", "Kỳ Nhông", "animals/giant_newt"),
    (5, "worker_ant", "Kiến Thợ", "animals/worker_ant"),
    (6, "giant_frog", "Ếch Khổng Lồ", "animals/giant_frog"),
    (7, "adder", "Rắn Lục", "animals/adder"),
    (8, "yellow_wasp", "Ong Vàng", "animals/yellow_wasp"),
    (9, "iguana", "Kỳ Đà", "animals/iguana"),
    (10, "soldier_ant", "Kiến Lính", "animals/soldier_ant"),
    (11, "wild_hound", "Chó Săn Hoang", "animals/hound"),
    (12, "killer_bee", "Ong Sát Thủ", "animals/killer_bee"),
    (13, "jelly", "Thạch Nhầy", "amorphous/jelly"),
    (14, "giant_leech", "Đỉa Khổng Lồ", "animals/giant_leech"),
    (15, "water_moccasin", "Rắn Nước", "animals/water_moccasin"),
    (16, "swamp_worm", "Giun Đầm Lầy", "aquatic/swamp_worm"),
    (17, "bog_body", "Xác Đầm Lầy", "undead/bog_body"),
    (18, "wandering_mushroom", "Nấm Đi Lạc", "fungi_plants/wandering_mushroom"),
    (19, "vine_stalker", "Dây Leo Săn Mồi", "fungi_plants/vine_stalker"),
    (20, "thorn_hunter", "Thợ Săn Gai", "fungi_plants/thorn_hunter"),
    (21, "scorpion", "Bọ Cạp", "animals/scorpion"),
    (22, "wild_yak", "Bò Yak", "animals/yak"),
    (23, "polar_bear", "Gấu Trắng", "animals/polar_bear"),
    (24, "ice_beast", "Thú Băng", "animals/ice_beast"),
    (25, "harpy", "Yêu Điểu", "harpy"),
    (26, "gnoll_sergeant", "Đội Trưởng Gnoll", "gnoll_sergeant"),
    (27, "griffon", "Sư Tử Đầu Ưng", "griffon"),
    (28, "satyr", "Thần Rừng Satyr", "satyr"),
    (29, "ghost", "Hồn Ma", "undead/ghost"),
    (30, "phantom", "Bóng Ma", "undead/phantom"),
    (31, "flying_skull", "Sọ Bay", "undead/flying_skull"),
    (32, "necrophage", "Kẻ Ăn Xác", "undead/necrophage"),
    (33, "revenant", "Kẻ Báo Thù", "undead/revenant"),
    (34, "earth_elemental", "Nguyên Tố Đất", "nonliving/earth_elemental"),
    (35, "fire_elemental", "Nguyên Tố Lửa", "nonliving/fire_elemental"),
    (36, "water_elemental", "Nguyên Tố Nước", "nonliving/water_elemental"),
    (37, "air_elemental", "Nguyên Tố Gió", "nonliving/air_elemental"),
    (38, "iron_golem", "Người Sắt", "nonliving/iron_golem"),
    (39, "crystal_guardian", "Vệ Binh Pha Lê", "nonliving/crystal_guardian"),
    (40, "ettin", "Khổng Lồ Hai Đầu", "ettin"),
    (41, "stone_giant", "Khổng Lồ Đá", "stone_giant"),
    (42, "frost_giant", "Khổng Lồ Băng", "frost_giant"),
    (43, "fire_giant", "Khổng Lồ Lửa", "fire_giant"),
    (44, "swamp_dragon", "Rồng Đầm", "dragons/swamp_dragon"),
    (45, "quicksilver_dragon", "Rồng Thủy Ngân", "dragons/quicksilver_dragon"),
    (46, "hell_hound", "Chó Địa Ngục", "animals/hell_hound"),
    (47, "red_devil", "Quỷ Đỏ", "demons/red_devil"),
    (48, "blizzard_demon", "Quỷ Bão Tuyết", "demons/blizzard_demon"),
    (49, "balrug", "Quỷ Lửa", "demons/balrug"),
    (50, "titan", "Titan", "titan"),
    (51, "reaper", "Thần Chết", "demons/reaper"),
    (52, "ancient_lich", "Cổ Vu Yêu", "undead/ancient_lich"),
]

def main(mon):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "priv/static/assets/monsters")
    for lv, mid, name, src in SPECIES:
        shutil.copyfile(os.path.join(mon, src + ".png"), os.path.join(out, mid + ".png"))
    data = {"SIDE_MONSTERS": [{"id": mid, "name": name, "level": lv} for lv, mid, name, _ in SPECIES]}
    with open(os.path.join(root, "priv/game_data/side.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(len(SPECIES), "loài")

if __name__ == "__main__":
    main(sys.argv[1])

#!/usr/bin/env python3
"""Sinh bản đồ phòng Hỗn Chiến Thành (DECISIONS "Sự kiện đánh chung theo phòng"): chép priv/maps/chaos_castle.json
(phòng 0) thành chaos_castle_<b>.json cho mỗi phòng b ≥ 1 của RULES.event_rooms.bands, tên ghi khoảng chuyển sinh.
Chạy lại khi đổi bands hoặc sửa bản đồ gốc:  python3 scripts/gen_cc_rooms.py"""
import json, os, glob

root = os.path.join(os.path.dirname(__file__), "..")
rules = json.load(open(os.path.join(root, "priv/game_data/rules.json"), encoding="utf-8"))["RULES"]
bands = rules["event_rooms"]["bands"]
max_rb = rules["character"]["max_rebirths"]
base = json.load(open(os.path.join(root, "priv/maps/chaos_castle.json"), encoding="utf-8"))


def label(lo, hi):
    if lo >= max_rb:
        return f"CS {lo}+"
    return f"CS {lo}" if lo == hi else f"CS {lo}–{hi}"


for old in glob.glob(os.path.join(root, "priv/maps/chaos_castle_*.json")):
    os.remove(old)

for b, (lo, hi) in enumerate(bands):
    if b == 0:
        continue
    m = dict(base, id=f"chaos_castle_{b}", name=f"{base['name'].split(' · ')[0]} · {label(lo, hi)}")
    with open(os.path.join(root, f"priv/maps/chaos_castle_{b}.json"), "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent=2)
        f.write("\n")
print(f"{len(bands) - 1} phòng")

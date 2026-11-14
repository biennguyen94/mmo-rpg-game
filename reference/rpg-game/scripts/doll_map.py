#!/usr/bin/env python3
# Bảng gán đồ → hình nhân vật ghép lớp (DECISIONS "Hình nhân vật Dungeon Crawl đủ lớp"): chép các hình dùng tới từ bộ
# tile Dungeon Crawl Stone Soup (CC0, bản "Full" và "Supplemental" trên OpenGameArt: player/…) vào
# priv/static/assets/doll/ và ghi priv/game_data/doll.json (khóa DOLL) cho Engine.look.
# Chạy: python3 scripts/doll_map.py <thư_mục_player_bản_Full> <thư_mục_player_bản_Supplemental>
# Sửa bảng ở dưới rồi chạy lại. Bản xem trước để duyệt: artifact "Bảng gán hình nhân vật".
import json, os, shutil, sys

CLASS = {
  'dk':  {'name':'Kiếm Sĩ','base':'base/human_male','hair':'hair/short_black','beard':None},
  'dw':  {'name':'Phù Thủy','base':'base/human_male','hair':'hair/long_white','beard':'beard/long_white'},
  'elf': {'name':'Tiên Nữ','base':'base/elf_female','hair':'hair/elf_yellow','beard':None},
  'mg':  {'name':'Đấu Sĩ','base':'base/human_male','hair':'hair/short_red','beard':'beard/short_red'},
}
# (tên bộ, cấp, lớp mẫu, mũ, giáp, quần, găng, giày, áo choàng)
SETS = [
 # Kiếm Sĩ (Đấu Sĩ mặc chung)
 ('Da',1,'dk','head/bandana_ybrown','body/leather_armor','legs/pants_brown','gloves/glove_brown','boots/short_brown',None),
 ('Đồng',3,'dk','head/iron_1','body/banded','legs/leg_armor_0','gloves/glove_orange','boots/middle_brown',None),
 ('Vảy',7,'dk','head/iron_2','body/scalemail','legs/leg_armor_1','gloves/glove_gray','boots/middle_gray',None),
 ('Đồng Thau',12,'dk','head/viking_brown_1','body/banded_2','legs/leg_armor_2','gloves/glove_orange','boots/middle_ybrown',None),
 ('Thép Tấm',17,'dk','head/iron_3','body/plate','legs/metal_gray','gloves/gauntlet_blue','boots/mesh_black',None),
 ('Rồng',22,'dk','head/art_dragonhelm','body/dragon_scale_green','legs/leg_armor_3','gloves/glove_red','boots/long_red','cloak/green'),
 ('Ánh Bạc',22,'dk','head/fhelm_gray_3','body/plate_2','legs/metal_gray','gloves/glove_white','boots/mesh_white','cloak/white'),
 ('Hắc Long',27,'dk','head/black_horn','body/dragon_armor_shadow','legs/leg_armor_4','gloves/glove_black','boots/mesh_black','cloak/black'),
 ('Kim Cương',27,'dk','head/fhelm_horn_2','body/crystal_plate','legs/metal_gray','gloves/gauntlet_blue','boots/blue_gold','cloak/cyan'),
 ('Quạ Tro',27,'dk','head/black_horn_2','body/plate_black','legs/leg_armor_4','gloves/glove_black_2','boots/mesh_black','cloak/gray'),
 ('Vinh Quang',27,'dk','head/helm_plume','body/armor_blue_gold','legs/leg_armor_5','gloves/glove_gold','boots/blue_gold','cloak/red'),
 ('Phượng Hoàng Đen',32,'dk','head/horn_evil','body/dragon_armor_magenta_new','legs/leg_armor_4','gloves/glove_purple','boots/middle_purple','cloak/magenta'),
 ('Thép Đen',32,'dk','head/full_black','body/breast_black','legs/leg_armor_3','gloves/glove_black','boots/mesh_black','cloak/black'),
 ('Titan',32,'dk','head/iron_red','body/bplate_metal_1','legs/leg_armor_5','gloves/gauntlet_blue','boots/mesh_red','cloak/red'),
 ('Dũng Sĩ',32,'dk','head/viking_gold','body/half_plate_2','legs/leg_armor_2','gloves/glove_gray','boots/middle_gold','cloak/blue'),
 ('Đại Long',40,'dk','head/art_dragonhelm','body/dragon_armor_gold_new','legs/leg_armor_5','gloves/glove_gold','boots/blue_gold','cloak/yellow'),
 ('Hắc Chủ',40,'dk','head/horns_3','body/dragon_scale_shadow','legs/leg_armor_4','gloves/glove_black','boots/mesh_black','cloak/dragonskin'),
 ('Long Kỵ Sĩ',48,'dk','head/fhelm_horn_yellow','body/dragon_armor_blue_new','legs/leg_armor_5','gloves/gauntlet_blue','boots/blue_gold','cloak/blue'),
 ('Ánh Dương',48,'dk','head/crown_gold_2','body/orange_crystal','legs/leg_armor_5','gloves/glove_gold','boots/middle_gold','cloak/yellow'),
 ('Bá Vương',48,'dk','head/crown_gold_3','body/dragon_armor_white_new','legs/leg_armor_5','gloves/glove_white','boots/mesh_white','cloak/red'),
 # Phù Thủy
 ('Vải Bông',1,'dw','head/hood_white','body/robe_white','legs/pants_l_white','gloves/glove_short_white','boots/short_brown',None),
 ('Xương',3,'dw','head/hood_gray','body/robe_gray_2','legs/skirt_white_2','gloves/glove_short_gray','boots/short_brown_2',None),
 ('Bí Ẩn',7,'dw','head/wizard_brown','body/robe_brown_2','legs/pants_brown','gloves/glove_short_white','boots/middle_brown',None),
 ('Nhân Sư',7,'dw','head/turban_brown','body/robe_yellow','legs/pants_orange','gloves/glove_short_yellow','boots/middle_ybrown',None),
 ('Huyền Thoại',12,'dw','head/wizard_blue','body/robe_blue','legs/pants_blue','gloves/glove_short_blue','boots/middle_gray',None),
 ('Cánh Đỏ',17,'dw','head/wizard_red','body/robe_red_gold','legs/pants_red','gloves/glove_short_red','boots/short_red',None),
 ('Nhật Thực',22,'dw','head/hood_black_2','body/robe_black_red','legs/skirt_red','gloves/glove_black','boots/mesh_red','cloak/black'),
 ('Cổ Đại',22,'dw','head/wizard_darkgreen','body/robe_green_gold','legs/pants_darkgreen','gloves/glove_short_green','boots/middle_green','cloak/brown'),
 ('Đại Linh Hồn',27,'dw','head/wizard_bluegreen','body/robe_blue_green','legs/skirt_blue','gloves/glove_blue','boots/mesh_blue','cloak/cyan'),
 ('Hồng Đen',27,'dw','head/wizard_blackred','body/robe_misfortune','legs/skirt_red','gloves/glove_red','boots/long_red','cloak/red'),
 ('Hồn Bóng Tối',32,'dw','head/hood_black_2','body/robe_of_night','legs/pants_black','gloves/glove_black_2','boots/mesh_black','cloak/black'),
 ('Diêm Vương',32,'dw','head/horn_evil','body/robe_black_hood','legs/pants_black','gloves/claws','boots/mesh_red','cloak/dragonskin'),
 ('Huệ Tây',40,'dw','head/wizard_white','body/robe_white_blue','legs/skirt_white','gloves/glove_white','boots/long_white','cloak/white'),
 ('Sương Độc',48,'dw','head/wizard_lightgreen','body/robe_green','legs/skirt_green','gloves/glove_short_green','boots/middle_green','cloak/green'),
 ('Hào Quang',48,'dw','head/wizard_blackgold','body/robe_black_gold','legs/pants_black','gloves/glove_gold','boots/blue_gold','cloak/yellow'),
 ('Nữ Hoàng',48,'dw','head/crown_gold_1','body/robe_purple','legs/skirt_white','gloves/glove_purple','boots/middle_purple','cloak/magenta'),
 # Tiên Nữ
 ('Dây Leo',1,'elf','head/feather_green','body/leather_green','legs/pants_darkgreen','gloves/glove_short_green','boots/middle_green',None),
 ('Lụa',3,'elf','head/band_white','body/dress_white','legs/skirt_white','gloves/glove_short_white','boots/long_white',None),
 ('Gió',7,'elf','head/feather_white','body/leather_short','legs/skirt_green','gloves/glove_short_white','boots/middle_green',None),
 ('Linh Hồn',12,'elf','head/hood_cyan','body/monk_blue','legs/skirt_blue','gloves/glove_short_blue','boots/mesh_blue',None),
 ('Hộ Vệ',17,'elf','head/helm_green','body/green_chain','legs/metal_green','gloves/glove_short_green','boots/middle_green',None),
 ('Diên Vĩ',22,'elf','head/feather_blue','body/dress_green','legs/skirt_green','gloves/glove_blue','boots/middle_green','cloak/blue'),
 ('Thần Thánh',27,'elf','head/healer','body/legolas','legs/trouser_green','gloves/glove_white','boots/long_white','cloak/white'),
 ('Linh Hồn Đỏ',32,'elf','head/feather_red','body/leather_red','legs/skirt_red','gloves/glove_red','boots/long_red','cloak/red'),
 ('Thiên Sứ',32,'elf','head/yellow_wing','body/arwen','legs/skirt_white','gloves/glove_white','boots/long_white','cloak/yellow'),
 ('Đức Tin',32,'elf','head/hood_white_2','body/robe_white_green','legs/skirt_white_2','gloves/glove_short_white','boots/mesh_white','cloak/cyan'),
 ('Tia Tiên',48,'elf','head/crown_gold_1','body/faerie_dragon_armor','legs/skirt_white','gloves/glove_gold','boots/blue_gold','cloak/magenta'),
 # Đấu Sĩ (không mũ)
 ('Quạ Bão',22,'mg',None,'body/plate_and_cloth','legs/leg_armor_1','gloves/glove_black','boots/mesh_black','cloak/gray'),
 ('Dũng Mãnh',27,'mg',None,'body/half_plate_3','legs/leg_armor_2','gloves/glove_red','boots/mesh_red','cloak/magenta'),
 ('Ưng Sấm',32,'mg',None,'body/dragon_scale_cyan_new','legs/leg_armor_3','gloves/gauntlet_blue','boots/mesh_blue','cloak/cyan'),
 ('Cuồng Phong',32,'mg',None,'body/dragon_scale_blue_new','legs/leg_armor_3','gloves/glove_blue','boots/blue_gold','cloak/blue'),
 ('Núi Lửa',48,'mg',None,'body/dragon_armor_brown_new','legs/leg_armor_5','gloves/glove_red','boots/long_red','cloak/red'),
 ('Hủy Diệt',48,'mg',None,'body/dragon_scale_shadow','legs/leg_armor_4','gloves/claws','boots/mesh_black','cloak/black'),
 ('Bóng Ma',48,'mg',None,'body/dragon_scale_quicksilver','legs/leg_armor_5','gloves/glove_white','boots/mesh_white','cloak/white'),
]
WEAPONS = {
 'item_0_0':'dagger_new','item_0_1':'short_sword','item_0_2':'rapier','item_0_3':'katana','item_0_4':'sword_thief',
 'item_0_5':'falchion_new','item_0_6':'short_sword_2','item_0_7':'scimitar_new','item_0_8':'sword_twist','item_0_9':'sword_seven',
 'item_0_10':'blessed_blade','item_0_11':'long_sword','item_0_12':'sword_tri','item_0_13':'double_sword_new','item_0_14':'sword_3',
 'item_0_15':'great_sword','item_0_16':'sword_black','item_0_17':'black_sword','item_0_18':'triple_sword_new','item_0_19':'sword_jag',
 'item_0_20':'long_sword_slant_new','item_0_21':'great_sword_slant_new','item_0_22':'sword_breaker','item_0_23':'triple_sword_2',
 'item_0_24':'heavy_sword','item_0_25':'double_sword_2','item_0_26':'sword_2','item_0_27':'sabre','item_0_28':'boromir','item_0_31':'aragorn',
 'item_1_0':'axe_small','item_1_1':'hand_axe_new','item_1_2':'axe_double','item_1_3':'axe_short','item_1_4':'axe',
 'item_1_5':'battleaxe','item_1_6':'battleaxe_2','item_1_7':'great_axe','item_1_8':'broad_axe',
 'item_2_0':'mace_new','item_2_1':'morningstar_new','item_2_2':'flail_ball_new','item_2_3':'great_mace','item_2_4':'eveningstar_new',
 'item_2_5':'gimli','item_2_6':'war_axe_new','item_2_7':'mace_ruby_new','item_2_8':'scepter','item_2_9':'rod_hammer_new',
 'item_2_10':'large_mace','item_2_11':'rod_moon_new','item_2_12':'rod_aries_new','item_2_13':'holy_scourge_1','item_2_14':'rod_ruby_new',
 'item_2_15':'rod_emerald_new','item_2_16':'rod_blue_new','item_2_17':'rod_magenta_new','item_2_18':'rod_thick_new',
 'item_3_0':'spear_3','item_3_1':'spear','item_3_2':'lance','item_3_3':'trident_2','item_3_4':'trident_two','item_3_5':'glaive_new',
 'item_3_6':'halberd_new','item_3_7':'glaive_2','item_3_8':'scythe_new','item_3_9':'glaive_three','item_3_10':'lance_2','item_3_11':'trishula',
 'item_4_0':'bow','item_4_1':'bow_2','item_4_2':'legolas','item_4_3':'bow_3','item_4_4':'great_bow','item_4_5':'bow_blue',
 'item_4_6':'great_bow','item_4_8':'crossbow','item_4_9':'crossbow_2','item_4_10':'crossbow_3','item_4_11':'hand_crossbow',
 'item_4_12':'crossbow_4','item_4_13':'crossbow_2','item_4_14':'crossbow_3','item_4_16':'crossbow_4','item_4_17':'bow_blue',
 'item_4_18':'crossbow_4','item_4_19':'crossbow_3','item_4_20':'bow_3','item_4_21':'legolas','item_4_22':'bow_2','item_4_23':'great_bow','item_4_24':'bow_blue',
 'item_5_0':'staff_skull','item_5_1':'staff_plain','item_5_2':'staff_organic','item_5_3':'staff_fork','item_5_4':'staff_evil',
 'item_5_5':'staff_fancy','item_5_6':'staff_ring_blue','item_5_7':'staff_mage','item_5_8':'staff_large','item_5_9':'great_staff',
 'item_5_10':'gandalf','item_5_11':'staff_mummy','item_5_12':'staff_organic','item_5_13':'staff_scepter','item_5_14':'quarterstaff',
 'item_5_15':'quarterstaff_2_new','item_5_16':'staff_ruby','item_5_17':'staff_mage_2','item_5_18':'staff_evil','item_5_19':'staff_ring_blue',
 'item_5_20':'staff_fancy','item_5_30':'saruman','item_5_31':'staff_scepter','item_5_32':'gandalf','item_5_33':'staff_ruby','item_5_34':'staff_skull',
 # đồ cơ bản (items.json)
 'club':'club','dagger':'dagger_new','broadsword':'broadsword','mace':'mace_new','battleaxe':'battleaxe','greatsword':'great_sword','waraxe':'war_axe_new','relic':'blessed_blade',
}
SHIELDS = {
 'item_6_0':'buckler_round_2','item_6_1':'buckler_spiral','item_6_2':'shield_kite_1','item_6_3':'lshield_green','item_6_4':'buckler_rb',
 'item_6_5':'shield_draconic_knight','item_6_6':'shield_skull','item_6_7':'shield_round_3','item_6_8':'shield_long_red','item_6_9':'shield_knight_gray',
 'item_6_10':'shield_round_5','item_6_11':'lshield_teal','item_6_12':'shield_middle_brown','item_6_14':'lshield_quartered','item_6_15':'shield_middle_cyan',
 'item_6_16':'lshield_spiral','item_6_17':'shield_long_cross','item_6_18':'shield_round_6','item_6_19':'shield_round_white','item_6_20':'shield_holy','item_6_21':'gil-galad',
 'round':'buckler_round_3','checked':'shield_knight_rw','spiked':'shield_kite_3','dragonshield':'lshield_gold',
}
BASIC_ARMOR = {'vest':'body/shirt_vest','leather':'body/leather_jacket','chain':'body/chainmail','scale':'body/scalemail_2','lamellar':'body/half_plate','breastplate':'body/bplate_metal_1'}

# lớp trong bộ tile → thư mục trong assets/doll
DIR = {'hand_right': 'hand1', 'hand_left': 'hand2'}
# mũ không che tóc (băng đô, lông vũ, vương miện…)
OPEN_HELM = ('band_', 'bandana', 'feather_', 'crown_', 'yellow_wing', 'taiso_', 'healer')
SLOTS = ['helm', 'armor', 'pants', 'gloves', 'boots', 'cloak']


def rel(p):
    """'hand_right/katana' → 'hand1/katana' (đường dẫn trong assets/doll, không đuôi)."""
    d, n = p.split('/', 1)
    return f'{DIR.get(d, d)}/{n}'


def main():
    roots = sys.argv[1:]
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(here, '..', 'priv', 'static', 'assets', 'doll')
    used = set()
    classes = {}
    for k, c in CLASS.items():
        classes[k] = {'body': c['base'], 'hair': c['hair'], 'beard': c['beard']}
        used.update(x for x in (c['base'], c['hair'], c['beard']) if x)
    sets = {}
    for (name, _lv, _cls, *parts) in SETS:
        m = {s: p for s, p in zip(SLOTS, parts) if p}
        used.update(m.values())
        sets[name] = {s: rel(p) for s, p in m.items()}
        if 'helm' in m:
            sets[name]['open'] = os.path.basename(m['helm']).startswith(OPEN_HELM)
    weapons = {k: rel('hand_right/' + v) for k, v in WEAPONS.items()}
    shields = {k: rel('hand_left/' + v) for k, v in SHIELDS.items()}
    used.update('hand_right/' + v for v in WEAPONS.values())
    used.update('hand_left/' + v for v in SHIELDS.values())
    used.update(BASIC_ARMOR.values())
    missing = []
    # hình cũ cùng tên mà khác ảnh (vd cung, nỏ tự vẽ của đồ cũ): hình mới lấy tên `…_dc`, không ghi đè
    renamed = {}
    for p in sorted(used):
        src = next((os.path.join(r, p + '.png') for r in roots if os.path.exists(os.path.join(r, p + '.png'))), None)
        if not src:
            missing.append(p)
            continue
        dst = os.path.join(out_dir, rel(p) + '.png')
        if os.path.exists(dst) and open(dst, 'rb').read() != open(src, 'rb').read() and not dst.endswith('_dc.png'):
            renamed[rel(p)] = rel(p) + '_dc'
            dst = os.path.join(out_dir, rel(p) + '_dc.png')
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)
    if missing:
        sys.exit('thiếu hình: ' + ', '.join(missing))
    fix = lambda v: renamed.get(v, v) if isinstance(v, str) else v
    classes = {k: {a: fix(b) for a, b in c.items()} for k, c in classes.items()}
    sets = {k: {a: fix(b) for a, b in c.items()} for k, c in sets.items()}
    weapons = {k: fix(v) for k, v in weapons.items()}
    shields = {k: fix(v) for k, v in shields.items()}
    doc = {
        '_doc': 'DECISIONS "Hình nhân vật Dungeon Crawl đủ lớp": ngoại hình theo đồ đang mặc (Engine.look). classes: thân, tóc, râu theo lớp; sets.<tên bộ>: helm / armor / pants / gloves / boots theo món đang mặc ở ô đó, cloak (áo choàng) theo bộ của giáp đang mặc, open: mũ không che tóc; weapons / shields: theo mã món; basic_armor: giáp cửa hàng cũ. Đường dẫn trong priv/static/assets/doll (không đuôi .png). Sinh bằng scripts/doll_map.py.',
        'sourceType': 'DESIGN', 'version': 1, 'verified': False,
        'classes': classes, 'sets': sets, 'weapons': weapons, 'shields': shields,
        'basic_armor': {k: fix(rel(v)) for k, v in BASIC_ARMOR.items()},
    }
    with open(os.path.join(here, '..', 'priv', 'game_data', 'doll.json'), 'w', encoding='utf-8') as f:
        json.dump({'DOLL': doc}, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print(f'đổi tên: {renamed}'); print(f'{len(used)} hình, {len(sets)} bộ, {len(weapons)} vũ khí, {len(shields)} khiên')


if __name__ == '__main__':
    main()

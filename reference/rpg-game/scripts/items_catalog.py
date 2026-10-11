#!/usr/bin/env python3
"""Sinh docs/ITEMS_CATALOG.md: danh sách mọi loại đồ (trang bị theo lớp / bậc, trang sức, cánh, ép +N, dòng phụ,
tỉ lệ rơi, vật phẩm khác), đọc thẳng từ priv/game_data. Chạy lại sau khi đổi dữ liệu đồ:

    python3 scripts/items_catalog.py
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, 'priv', 'game_data')
OUT = os.path.join(ROOT, 'docs', 'ITEMS_CATALOG.md')


def load(name, key=None):
    with open(os.path.join(DATA, name), encoding='utf-8') as f:
        d = json.load(f)
    return d[key] if key else d


mu = load('items_mu.json', 'ITEMS_MU')
leg = load('items.json', 'ITEMS')
up = load('upgrade.json')
rules = load('rules.json')
rules = rules.get('RULES', rules)
pick = load('item_pick.json', 'ITEM_PICK')
chaos = load('chaos.json')
chaos = chaos.get('CHAOS', chaos)

CLS = {'dk': 'Kiếm Sĩ', 'dw': 'Phù Thủy', 'elf': 'Tiên Nữ', 'mg': 'Đấu Sĩ'}
ARMOR = ('helm', 'armor', 'pants', 'gloves', 'boots')
KIND = {'normal': 'Quái thường', 'night': 'Quái đêm', 'elite': 'Tinh anh', 'boss': 'Trùm'}
items = list(mu.values())


def pct(x):
    return f"{x * 100:.1f}".rstrip('0').rstrip('.').replace('.', ',') + '%'


def num(x):
    return f"{x:,}".replace(',', '.')


def nm(i):
    # món phụ in nghiêng
    return f"*{i['name']}*" if i.get('alt') else f"**{i['name']}**"


def table(head, rows):
    out = ['| ' + ' | '.join(head) + ' |', '|' + '---|' * len(head)]
    out += ['| ' + ' | '.join(str(c) for c in r) + ' |' for r in rows]
    return '\n'.join(out)


lv, pr, st = pick['levels'], pick['prices'], pick['stats']
md = []
w = md.append

w('# Danh mục đồ Hắc Long\n')
w('> File sinh tự động bằng `python3 scripts/items_catalog.py` từ `priv/game_data` — đừng sửa tay, '
  'đổi dữ liệu rồi chạy lại.\n')

# ---------- tổng quan ----------
alt_n = sum(1 for i in items if i.get('alt'))
sets_main = len({i['set'] for i in items if i.get('set') and not i.get('alt')})
sets_alt = len({i['set'] for i in items if i.get('set') and i.get('alt')})
w('## Tổng quan\n')
w(f"- **{len(items)} món trang bị**, trong đó **{alt_n} món phụ** (chỉ rơi, không bán).")
w(f"- **8 bậc** đồ; ép tối đa **+{up['UPGRADE']['max']}**; **{sets_main} bộ giáp chính + {sets_alt} bộ phụ**.")
w('- Ô trang bị: vũ khí, khiên, mũ, giáp, quần, găng, giày, 2 nhẫn, dây chuyền, cánh. Đấu Sĩ không đội mũ.')
w('- Món phụ có công, thủ, cấp và giá như món chính cùng bậc; chỉ khác tên, hình và yêu cầu chỉ số.\n')


def group(i):
    return 'Bộ giáp (món)' if i['slot'] in ARMOR else {
        'weapon': 'Vũ khí', 'shield': 'Khiên', 'ring': 'Nhẫn', 'pendant': 'Dây chuyền'}[i['slot']]


rows = []
for g in ['Vũ khí', 'Khiên', 'Bộ giáp (món)', 'Nhẫn', 'Dây chuyền']:
    main = sum(1 for i in items if group(i) == g and not i.get('alt'))
    alt = sum(1 for i in items if group(i) == g and i.get('alt'))
    rows.append([g, main, alt or '—'])
w(table(['Loại', 'Món chính', 'Món phụ'], rows) + '\n')

# ---------- theo lớp ----------
w('## Đồ theo lớp\n')
w('**Đậm**: món chính (bán ở cửa hàng). *Nghiêng*: món phụ (chỉ rơi). '
  'Công: trung bình (thấp ~ cao) của món chính.\n')
for cls, cname in CLS.items():
    w(f'### {cname}\n')
    rows = []
    for t in range(1, 9):
        ws = sorted((i for i in items if i['slot'] == 'weapon' and i['tier'] == t and cls in i['classes']),
                    key=lambda i: (bool(i.get('alt')), i['name']))
        w0 = next((i for i in ws if not i.get('alt')), ws[0] if ws else None)
        sets = {}
        for i in items:
            if i.get('set') and i['tier'] == t and cls in i['classes']:
                sets.setdefault(i['set'], bool(i.get('alt')))
        sets = sorted(sets.items(), key=lambda x: (x[1], x[0]))
        first = sets[0][0] if sets else None
        setdef = sum(i['def'] for i in items
                     if i.get('set') == first and i['tier'] == t and cls in i['classes'])
        sh = sorted((i for i in items if i['slot'] == 'shield' and i['tier'] == t and cls in i['classes']),
                    key=lambda i: (bool(i.get('alt')), i['name']))
        rows.append([
            t, lv['weapon'][t - 1],
            ', '.join(nm(i) for i in ws),
            f"{w0['atk']} ({w0['atkMin']}~{w0['atkMax']})" if w0 else '—',
            ', '.join(f'*{s}*' if a else f'**{s}**' for s, a in sets),
            setdef,
            ', '.join(nm(i) for i in sh) or '—',
        ])
    w(table(['Bậc', 'Cấp', 'Vũ khí', 'Công', 'Bộ giáp', 'Thủ cả bộ', 'Khiên'], rows) + '\n')

# ---------- bậc / cấp / giá ----------
sb = rules['set_bonus']
w('## Bậc, cấp, giá\n')
w('Mọi lớp dùng chung. Giá bộ giáp là giá đủ bộ, chia cho từng món theo tỉ lệ thủ. Bậc 1 là đồ khởi đầu '
  f"(giá 0). Bán lại cho NPC được {pct(rules['shop']['sell_ratio'])} giá.\n")
rows = [[t, lv['weapon'][t - 1], num(pr['weapon'][t - 1]), num(pr['set'][t - 1]), st['set_def'][t - 1],
         lv['shield'][t - 1], num(pr['shield'][t - 1]), st['shield_def'][t - 1]] for t in range(1, 9)]
w(table(['Bậc', 'Cấp vũ khí / giáp', 'Giá vũ khí', 'Giá bộ giáp', 'Thủ cả bộ', 'Cấp khiên', 'Giá khiên',
         'Thủ khiên'], rows) + '\n')
w(f"Thưởng đủ bộ (từ bậc {sb['min_tier']}): +{pct(sb['def_pct'])} thủ, +{pct(sb['atk_pct'])} công, "
  f"+{sb['hp_per_tier']} máu × bậc bộ.\n")

# ---------- trang sức ----------
jw = pick['jewelry']
w('## Nhẫn, dây chuyền\n')
w('Chỉ rơi từ quái và rương, mọi lớp dùng được, không đòi chỉ số. Đeo 2 nhẫn + 1 dây chuyền.\n')
rows = [['Nhẫn', f"**{j['name']}**", j['level'],
         f"+{j['hp']} máu" if 'hp' in j else f"+{j['def']} thủ", num(j['price'])] for j in jw['ring']]
rows += [['Dây chuyền', f"**{j['name']}**", j['level'], f"+{j['atk']} công", num(j['price'])]
         for j in jw['pendant']]
w(table(['Loại', 'Tên', 'Cấp', 'Chỉ số', 'Giá'], rows) + '\n')

# ---------- cánh ----------
wings = [v for v in leg.values() if v.get('slot') == 'wing']
recipe = {c['out']: c for c in chaos if isinstance(c, dict) and str(c.get('out', '')).startswith('wing_')}
w('## Cánh\n')
w(f"Ghép ở Máy Hỗn Nguyên. Mỗi cấp ép cánh thêm {pct(rules['combat']['wing_per_level'])} sát thương và hấp thụ.\n")
rows = []
for t in (1, 2, 3):
    ws = [x for x in wings if x['tier'] == t]
    x = ws[0]
    wo = next((o for o in rules['wing_options']['by_tier'] if o['tier'] == t), None)
    r = recipe.get(f'wing_{{cls}}_{t}', {})
    rows.append([
        t, ', '.join(f"{y['name']} ({CLS[y['cls']]})" for y in ws), x['level'], x['def'],
        '+' + pct(x['dmg']), '−' + pct(x['absorb']),
        f"1 dòng: +{wo['hp']} máu / +{wo['mp']} MP / bỏ qua {pct(wo['ignore_def'])} thủ" if wo else '—',
        f"{r.get('desc', '')} {num(r['gold'])} vàng, {pct(r['rate'])}" if r else '—',
    ])
w(table(['Cấp', 'Tên theo lớp', 'Cấp đeo', 'Thủ', 'Sát thương', 'Nhận vào', 'Dòng phụ', 'Cách ghép'], rows) + '\n')

# ---------- ép ----------
U, ur, ls = up['UPGRADE'], rules['upgrade'], rules['luck_skill']
jn = {k: v['name'] for k, v in leg.items() if k.startswith('jewel')}
fail = {None: '—', 'down': 'tụt 1 cấp', 'reset': '**về +0**', 'destroy': '**vỡ đồ**'}
where = {'smith': 'Thợ Rèn', 'chaos': 'Máy Hỗn Nguyên'}


def eff(l):
    return l + max(0, l - U['double_from'] + 1)


w('## Ép +N (kiểu MU)\n')
w(f"Mỗi cấp cộng {pct(ur['bonus_pct'])} chỉ số gốc của món (ít nhất +1). Từ +{U['double_from']} mỗi cấp tính "
  f"gấp đôi. Từ +{U['announce_from']} cả bản đồ thấy thông báo. Đồ có May mắn: tỉ lệ các bước không chắc chắn cộng "
  f"{pct(ls['luck_upgrade'])}, tối đa {pct(ls['luck_max_rate'])}.\n")
rows = []
for s in U['steps']:
    need = ' + '.join(f"{n} {jn[k]}" for k, n in s['items'].items())
    rows.append([f"+{s['level']}", where[s['at']], f"vàng + {need}", pct(s['rate']), fail[s['fail']], eff(s['level'])])
w(table(['Lên', 'Ở đâu', 'Cần', 'Tỉ lệ', 'Thất bại', 'Tính như (cấp)'], rows) + '\n')
life = ur['life']
w(f"Vàng = {pct(ur['cost_pct'])} giá món × cấp lên (giá tối thiểu {ur['cost_min_price']}). Ngọc Sinh Mệnh: "
  f"+{life['per_line']} mỗi dòng, tối đa "
  f"{life['max_lines']} dòng, {pct(life['rate'])}; vũ khí cộng công, giáp / khiên / cánh cộng thủ; thất bại mất "
  'dòng cuối.\n')

# ---------- dòng phụ ----------
ex, an, lo = rules['excellent'], rules['ancient'], rules['loot']
exn = {'atk_pct': 'Tấn công +{}', 'crit': 'Chí mạng +{}', 'heal_kill': 'Hồi {} máu khi hạ quái',
       'mp_kill': 'Hồi {} MP khi hạ quái', 'hp_pct': 'Máu tối đa +{}', 'dmg_red': 'Giảm sát thương nhận {}',
       'gold_pct': 'Vàng nhận +{}', 'atk_lvl': 'Tấn công + cấp × {}', 'ar_pct': 'Tỉ lệ trúng +{}',
       'mp_pct': 'MP tối đa +{}', 'reflect': 'Phản sát thương {}', 'def_rate': 'Tỉ lệ né +{}'}
w('## Dòng phụ trên đồ rơi\n')
w('### Dòng cộng thêm (kiểu MU, DECISIONS B-15)\n')
life = rules['upgrade']['life']
tot = sum(wt for _, wt in lo['gear_weights'])
for r, wt in lo['gear_weights']:
    lab = f"+{r * life['per_line']}" if r else 'Không dòng'
    w(f"- {lab} ({round(wt * 100 / tot)}%)")
w(f"\nMỗi dòng +{life['per_line']} tấn công (vũ khí) / phòng thủ (đồ khác); Ngọc Sinh Mệnh thêm dòng tới tối đa {life['max_lines']}. Không còn độ hiếm Tốt / Hiếm / Sử Thi.\n")
w('### Excellent\n')
w('Số dòng: ' + ', '.join(f"{n} dòng {wt}%" for n, wt in ex['lines']) + f". Giá bán ×{ex['price_mult']}.\n")
w('- Vũ khí, dây chuyền: ' + '; '.join(exn[k].format(v if k == 'atk_lvl' else pct(v)) for k, v in ex['options']['weapon'].items()))
w('- Giáp, khiên, nhẫn: ' + '; '.join(exn[k].format(v if k == 'atk_lvl' else pct(v)) for k, v in ex['options']['armor'].items()))
w(f"\nTổng giảm sát thương tối đa {pct(ex['max_dmg_red'])}. Pha thêm ở Máy Hỗn Nguyên (tối đa 3 dòng).\n")
w('### Đồ Thần\n')
w(f"Chỉ món bộ giáp. Thủ món +{pct(an['piece_def_pct'])}, giá bán ×{an['price_mult']}. "
  'Thưởng theo số món Thần cùng bộ, cộng dồn:\n')
for b in an['bonus']:
    parts = [f"+{pct(b['atk_pct'])} công" if b['atk_pct'] else '', f"+{pct(b['def_pct'])} thủ" if b['def_pct'] else '',
             f"+{b['hp']} máu" if b['hp'] else '']
    w(f"- **{'Đủ bộ' if b['count'] == 'full' else str(b['count']) + ' món'}**: " + ', '.join(p for p in parts if p))
w('\n### May mắn, Kỹ năng\n')
w(f"- **May mắn**: vũ khí +{pct(ls['luck_crit'])} chí mạng; mọi món +{pct(ls['luck_upgrade'])} tỉ lệ ép +7 đến +11.")
w(f"- **Kỹ năng** (chỉ vũ khí): chiêu +{pct(ls['skill_dmg'])} sát thương.")
w(f"- Mỗi dòng giá bán ×{str(ls['price_mult']).replace('.', ',')}. Pha May mắn ở Máy Hỗn Nguyên.\n")

# ---------- tỉ lệ rơi ----------
w('## Tỉ lệ rơi\n')
slots = lo['gear_slots']
prev, sl = 0, []
for edge, s in slots:
    sl.append(f"{ {'weapon': 'vũ khí', 'set': 'bộ giáp', 'shield': 'khiên', 'jewelry': 'trang sức'}[s]} "
              f"{pct(edge - prev)}")
    prev = edge
w('"Rơi đồ" là tỉ lệ mỗi con rơi một món trang bị; các cột sau tính trên món đã rơi (Thần chỉ tính món bộ giáp). '
  'Món rơi thuộc 2 mức cấp cao nhất không vượt cấp quái, đúng lớp người hạ: ' + ', '.join(sl) + '.\n')
rows = [[KIND[k], pct(lo['gear_chance'][k]), pct(ex['chance'][k]), pct(an['chance'][k]),
         pct(ls['luck_chance'][k]), pct(ls['skill_chance'])] for k in KIND]
w(table(['Loại quái', 'Rơi đồ', 'Excellent', 'Thần', 'May mắn', 'Kỹ năng'], rows) + '\n')
set_share = slots[1][0] - slots[0][0]
n = lo['gear_chance']['normal']
w(f"Quái thường: khoảng 1/{round(1 / (n * ex['chance']['normal']))} con ra Excellent, "
  f"1/{round(1 / (n * set_share * an['chance']['normal']))} con ra đồ Thần. Ngọc rơi riêng: quái từ cấp "
  f"{load('upgrade.json')['JEWELS']['monster_level']} có {pct(up['JEWELS']['monster_chance'])} mỗi con, "
  f"trùm {pct(up['JEWELS']['boss_chance'])}.\n")

# ---------- vật phẩm khác ----------
w('## Vật phẩm khác\n')
others = [
    ('Bình máu', [v for k, v in leg.items() if k.startswith('potion')], lambda v: f"hồi {pct(v['heal_pct'])} máu"),
    ('Bình mana', [v for k, v in leg.items() if k.startswith('mana')], lambda v: f"hồi {pct(v['mana_pct'])} MP"),
    ('Món ăn', [v for v in leg.values() if v.get('slot') == 'food'], lambda v: v['desc']),
    ('Ngọc', [v for k, v in leg.items() if k.startswith('jewel')], lambda v: v['desc']),
    ('Vé, nguyên liệu sự kiện', [leg[k] for k in ('ds_ticket', 'bc_ticket', 'condor_feather') if k in leg],
     lambda v: v['desc']),
    ('Nguyên liệu thu thập', [v for k, v in leg.items() if v.get('slot') == 'material' and v.get('sprite')
                              and not k.startswith(('moon', 'pumpkin', 'gift', 'lucky'))], lambda v: v['desc']),
    ('Quà lễ hội', [leg[k] for k in ('moon_cake', 'pumpkin_candy', 'gift_box', 'lucky_apple') if k in leg],
     lambda v: v['desc']),
]
for g, lst, f in others:
    w(f'### {g} ({len(lst)})\n')
    w(table(['Tên', 'Công dụng', 'Giá'], [[f"**{v['name']}**", f(v), num(v['price'])] for v in lst]) + '\n')
w('Giá 0: không bán ở cửa hàng (vé mua ở Người Gác Tháp). Giá bình thuốc ở cửa hàng tăng theo cấp nhân vật.')

with open(OUT, 'w', encoding='utf-8') as f:
    f.write('\n'.join(md) + '\n')
print(f'Đã ghi {os.path.relpath(OUT, ROOT)}: {len(items)} món trang bị.')

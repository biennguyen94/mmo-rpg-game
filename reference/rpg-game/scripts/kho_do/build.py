"""Sinh trang "Kho Đồ Hắc Long" từ dữ liệu game (data.json do export.exs ghi) + bảng hình Pixel."""
import json, html, sys, os
from collections import defaultdict

D = json.load(open(sys.argv[1], encoding="utf-8"))
PIX = json.load(open(sys.argv[2], encoding="utf-8"))
OUT = sys.argv[3]
IT, R, CL = D["items"], D["rules"], D["classes"]
SHOP = set(D["shop"])
USED = set()
CLS = [("dk", "Kiếm Sĩ"), ("dw", "Phù Thủy"), ("elf", "Tiên Nữ"), ("mg", "Đấu Sĩ")]
ARMOR = ["helm", "armor", "pants", "gloves", "boots"]
E = html.escape


def n(x):
    if isinstance(x, float) and x.is_integer():
        x = int(x)
    return f"{x:,}" if isinstance(x, int) else str(x).replace(".", ",")


def pct(x):
    v = round(x * 100, 1)
    return (str(int(v)) if v == int(v) else str(v).replace(".", ",")) + "%"


def ic(i):
    p = PIX.get(i)
    if not p:
        return ""
    USED.add(p)
    return f'<img class="px" src="{p}" alt="" width="24" height="24" loading="lazy">'


def nm(it, bold=None):
    b = (not it.get("alt")) if bold is None else bold
    name = E(it["name"]) + (' <span class="shop" title="Bán ở Thợ Rèn">🛒</span>' if it["id"] in SHOP else "")
    inner = f"{ic(it['id'])}<b>{name}</b>" if b else f'{ic(it["id"])}<span class="alt">{name}</span>'
    return f'<span class="it">{inner}</span>'


mu = [v for v in IT.values() if v.get("sourceType") == "MU_ITEM_TXT"]
gear = lambda cls, slot: [v for v in mu if v["slot"] == slot and cls in v.get("classes", [])]
tiers = sorted({v["tier"] for v in mu})
sets = {v["set"] for v in mu if v.get("set")}
wings = sorted([v for v in IT.values() if v["slot"] == "wing"], key=lambda v: (v["tier"], v["cls"]))

# ---------- Tổng quan ----------
slot_names = [("weapon", "Vũ khí"), ("shield", "Khiên"), ("helm", "Mũ"), ("armor", "Giáp"), ("pants", "Quần"),
              ("gloves", "Găng"), ("boots", "Giày"), ("ring", "Nhẫn"), ("pendant", "Dây chuyền")]
rows = "".join(
    f"<tr><td>{l}</td><td class=n>{sum(1 for v in mu if v['slot']==s and not v.get('alt'))}</td>"
    f"<td class=n>{sum(1 for v in mu if v['slot']==s and v.get('alt')) or '—'}</td></tr>" for s, l in slot_names)
overview = f"""
  <div class="stats">
    <div class="stat"><b>{len(mu) + len(wings)}</b><span>món trang bị (gồm {len(wings)} cánh)</span></div>
    <div class="stat"><b>{len(tiers)}</b><span>bậc đồ</span></div>
    <div class="stat"><b>+{D['upgrade']['max']}</b><span>ép tối đa</span></div>
    <div class="stat"><b>{len(sets)}</b><span>bộ giáp</span></div>
    <div class="stat"><b>40</b><span>kỹ năng tháp (10 mỗi lớp)</span></div>
    <div class="stat"><b>10</b><span>vùng đất chuyển sinh</span></div>
  </div>
  <div class="scroll" style="max-width:460px"><table>
    <thead><tr><th>Loại</th><th>Món chính</th><th>Món phụ</th></tr></thead><tbody>{rows}</tbody></table></div>
  <p class="note">Ô trang bị: vũ khí, khiên, mũ, giáp, quần, găng, giày, 2 nhẫn, dây chuyền, cánh, thú nuôi. Đấu Sĩ không đội mũ.
  Món phụ có công, thủ, cấp như món chính cùng bậc, chỉ khác tên, hình và yêu cầu chỉ số. 🛒: bán ở Thợ Rèn (đồ cấp ≤ {R['shop']['smith_max_level']});
  đồ cao hơn chỉ có từ quái, rương, sự kiện, chợ. Hình đồ trên trang là bộ <b>Pixel</b> trong game (CC0, Dungeon Crawl Stone Soup).</p>"""

# ---------- Đồ theo lớp ----------
def class_table(c):
    out = []
    for t in tiers:
        w = sorted([v for v in gear(c, "weapon") if v["tier"] == t], key=lambda v: (bool(v.get("alt")), v["name"]))
        arm = [v for s in ARMOR for v in gear(c, s) if v["tier"] == t]
        sh = sorted([v for v in gear(c, "shield") if v["tier"] == t], key=lambda v: (bool(v.get("alt")), v["name"]))
        if not (w or arm or sh):
            continue
        mains = [v for v in w if not v.get("alt")] or w
        atk = ""
        if mains:
            lo = round(sum(v["atkMin"] for v in mains) / len(mains)); hi = round(sum(v["atkMax"] for v in mains) / len(mains))
            atk = f"{round((lo+hi)/2)} ({lo}~{hi})"
        by_set = defaultdict(list)
        for v in arm:
            by_set[(bool(v.get("alt")), v.get("set") or v["name"])].append(v)
        set_cells, main_def = [], None
        for (alt, sname), pieces in sorted(by_set.items()):
            body = next((p for p in pieces if p["slot"] == "armor"), pieces[0])
            label = f'{ic(body["id"])}' + (f"<b>{E(sname)}</b>" if not alt else f'<span class="alt">{E(sname)}</span>')
            set_cells.append(f'<span class="it">{label}</span>')
            if not alt and main_def is None:
                main_def = sum(p.get("def", 0) for p in pieces)
        lvl = min([v["level"] for v in w + arm] or [0])
        shc = ", ".join(nm(v) for v in sh)
        shd = f"{sh[0].get('def', 0)} · c{sh[0]['level']}" if sh else "—"
        out.append(f"<tr><td class=n>{t}</td><td class=n>{lvl}</td><td>{', '.join(nm(v) for v in w) or '—'}</td>"
                   f"<td class=n>{atk or '—'}</td><td>{', '.join(set_cells) or '—'}</td><td class=n>{main_def if main_def is not None else '—'}</td>"
                   f"<td>{shc or '—'}</td><td class=n>{shd}</td></tr>")
    return ("<div class=\"scroll\"><table><thead><tr><th>Bậc</th><th>Cấp</th><th>Vũ khí</th><th>Công</th><th>Bộ giáp</th>"
            "<th>Thủ cả bộ</th><th>Khiên</th><th>Thủ · cấp</th></tr></thead><tbody>" + "".join(out) + "</tbody></table></div>")

tabs = "".join(f'<button type="button" class="tab" data-g="cls" data-c="{c}">{l}</button>' for c, l in CLS)
panes = "".join(f'<div class="ctab" data-g="cls" data-c="{c}"{" hidden" if i else ""}>{class_table(c)}</div>' for i, (c, _) in enumerate(CLS))

# ---------- Bậc, cấp, giá ----------
def rng(xs):
    xs = [x for x in xs if x is not None]
    if not xs:
        return "—"
    a, b = min(xs), max(xs)
    return n(a) if a == b else f"{n(a)}–{n(b)}"

trows = ""
for t in tiers:
    ws = [v for v in mu if v["slot"] == "weapon" and v["tier"] == t and not v.get("alt")]
    ar = [v for v in mu if v["slot"] in ARMOR and v["tier"] == t and not v.get("alt")]
    sh = [v for v in mu if v["slot"] == "shield" and v["tier"] == t]
    trows += (f"<tr><td class=n>{t}</td><td class=n>{rng([v['level'] for v in ws])}</td><td class=n>{rng([v['price'] for v in ws])}</td>"
              f"<td class=n>{rng([v['level'] for v in ar])}</td><td class=n>{rng([v['price'] for v in ar])}</td>"
              f"<td class=n>{rng([v['level'] for v in sh])}</td><td class=n>{rng([v.get('def') for v in sh])}</td></tr>")
sb = R["set_bonus"]

# ---------- Trang sức ----------
def jstat(v):
    return ", ".join(s for s in [f"+{v['hp']} máu" if v.get("hp") else "", f"+{v['def']} thủ" if v.get("def") else "",
                                f"+{v['atk']} công" if v.get("atk") else ""] if s)
jew = sorted([v for v in mu if v["slot"] in ("ring", "pendant")], key=lambda v: (v["slot"] != "ring", v["level"]))
jrows = "".join(f"<tr><td>{'Nhẫn' if v['slot']=='ring' else 'Dây chuyền'}</td><td>{nm(v, True)}</td><td class=n>{v['level']}</td>"
                f"<td>{jstat(v)}</td><td class=n>{n(v['price'])}</td></tr>" for v in jew)

# ---------- Cánh ----------
wo = {w["tier"]: w for w in R["wing_options"]["by_tier"]}
wrows = ""
for t in sorted({w["tier"] for w in wings}):
    ws = [w for w in wings if w["tier"] == t]
    names = ", ".join(f'<span class="it">{ic(w["id"])}{E(w["name"])} ({dict(CLS)[w["cls"]]})</span>' for w in ws)
    w0 = ws[0]
    opt = wo.get(t)
    optt = f"1 dòng: +{opt['hp']} máu / +{opt['mp']} MP / bỏ qua {pct(opt['ignore_def'])} thủ" if opt else "—"
    wrows += (f"<tr><td class=n>{t}</td><td>{names}</td><td class=n>{w0['level']}</td><td class=n>{w0['def']}</td>"
              f"<td class=n>+{pct(w0['dmg'])}</td><td class=n>−{pct(w0['absorb'])}</td><td>{optt}</td></tr>")

# ---------- Ép ----------
up = D["upgrade"]
FAIL = {None: "—", "down": "tụt 1 cấp", "reset": "<span class=bad>về +0</span>", "destroy": "<span class=bad>vỡ đồ</span>"}
AT = {"smith": "Thợ Rèn", "chaos": "Máy Hỗn Nguyên"}
erows = ""
for s in up["steps"]:
    lv = s["level"]
    eff = lv if lv < up["double_from"] else up["double_from"] - 1 + 2 * (lv - up["double_from"] + 1)
    need = " + ".join(f"{k2} {IT[k]['name']}" for k, k2 in s["items"].items())
    erows += (f"<tr><td class=n>+{lv}</td><td>{AT.get(s['at'], s['at'])}</td><td>vàng + {need}</td><td class=n>{pct(s['rate'])}</td>"
              f"<td>{FAIL.get(s.get('fail'), s.get('fail'))}</td><td class=n>{eff}</td></tr>")
ls = R["luck_skill"]; life = R["upgrade"]["life"]

# ---------- Dòng phụ ----------
EXC = {"atk_pct": "Tấn công +{}", "crit": "Chí mạng +{}", "heal_kill": "Hồi {} máu khi hạ quái", "mp_kill": "Hồi {} MP khi hạ quái",
       "atk_lvl": "Tấn công + cấp × {}", "ar_pct": "Tỉ lệ trúng +{}", "hp_pct": "Máu tối đa +{}", "dmg_red": "Giảm sát thương nhận {}",
       "gold_pct": "Vàng nhận +{}", "mp_pct": "MP tối đa +{}", "reflect": "Phản {} sát thương quái", "def_rate": "Né +{}"}
ex = R["excellent"]
def exl(group):
    return "".join(f"<li>{EXC[k].format(n(v) if k == 'atk_lvl' else pct(v))}</li>" for k, v in ex["options"][group].items())
anc = R["ancient"]
anc_li = "".join(
    f"<li><b>{'Đủ bộ' if b['count']=='full' else str(b['count']) + ' món'}</b>: " +
    ", ".join(x for x in [f"+{pct(b['atk_pct'])} công" if b["atk_pct"] else "", f"+{pct(b['def_pct'])} thủ" if b["def_pct"] else "",
                          f"+{b['hp']} máu" if b["hp"] else ""] if x) + "</li>" for b in anc["bonus"])
gw = R["loot"]["gear_weights"]; tot = sum(w for _, w in gw)
opt_li = "".join(f"<li><b>{k} dòng</b>: {pct(w/tot)}</li>" for k, w in gw)

# ---------- Tỉ lệ rơi ----------
KIND = [("normal", "Quái thường"), ("night", "Quái đêm"), ("elite", "Tinh anh"), ("boss", "Trùm")]
lrows = "".join(f"<tr><td>{l}</td><td class=n>{pct(R['loot']['gear_chance'][k])}</td><td class=n>{pct(ex['chance'][k])}</td>"
                f"<td class=n>{pct(anc['chance'][k])}</td><td class=n>{pct(ls['luck_chance'][k])}</td><td class=n>{pct(ls['skill_chance'])}</td></tr>"
                for k, l in KIND)
gs = R["loot"]["gear_slots"]; prev = 0; slot_txt = []
SL = {"weapon": "vũ khí", "set": "bộ giáp", "shield": "khiên", "jewelry": "trang sức"}
for p, s in gs:
    slot_txt.append(f"{SL[s]} {pct(p - prev)}"); prev = p
rl = R["realms"]

# ---------- Kỹ năng ----------
EL = R["elements"]
def el(e):
    return f'{EL["icons"][e]} {EL["names"][e]}' if e else "—"
BUFF = {"rage": "cuồng nộ +{} công", "guard": "thủ thế −{} sát thương nhận", "evade": "né +{}", "shield": "khiên hấp thụ {} máu tối đa",
        "undying": "bất tử: gục thì đứng dậy với {} máu (1 lần)"}
DEBUFF = {"weaken": "suy yếu quái −{} công", "sunder": "phá giáp quái −{} thủ", "poison": "độc: mỗi lượt {} sát thương vừa gây",
          "burn": "đốt: mỗi lượt {} sát thương vừa gây"}
def sdesc(k):
    p = []
    if k.get("hits", 1) > 1: p.append(f"{k['hits']} đòn")
    if k.get("def_mult") is not None: p.append(f"xuyên {pct(1 - k['def_mult'])} giáp")
    if k.get("crit"): p.append("chắc chí mạng")
    if k.get("heal"): p.append(f"hồi {pct(k['heal'])} máu")
    if k.get("drain"): p.append(f"hút {pct(k['drain'])} sát thương")
    if k.get("stun"): p.append(f"{pct(k['stun'])} làm quái mất lượt")
    if k.get("buff"): b = k["buff"]; p.append(BUFF.get(b["id"], b["id"]).format(pct(b["power"])) + f" ({b['turns']} lượt)")
    if k.get("debuff"): b = k["debuff"]; p.append(DEBUFF.get(b["id"], b["id"]).format(pct(b["power"])) + f" ({b['turns']} lượt)")
    return ", ".join(p) or "đòn mạnh"
def skill_table(c):
    rows = ""
    for k in CL[c].get("skills", []):
        rows += (f"<tr><td>cấp {k.get('level', 1)}</td><td><b>{E(k['name'])}</b></td><td>{el(k.get('element'))}</td>"
                 f"<td class=n>{'×' + n(k['mult']) if 'mult' in k else '—'}</td><td class=n>{k.get('mp', 0)}</td><td class=n>{k.get('cooldown', 0)}</td><td>{E(k.get('desc') or sdesc(k))}</td></tr>")
    for k in CL[c]["tower_skills"]:
        rows += (f"<tr><td>tháp {k['floor']}</td><td><b>{E(k['name'])}</b></td><td>{el(k.get('element'))}</td>"
                 f"<td class=n>×{n(k['mult'])}</td><td class=n>{k['mp']}</td><td class=n>{k['cooldown']}</td><td>{sdesc(k)}</td></tr>")
    return ("<div class=\"scroll\"><table><thead><tr><th>Mở</th><th>Kỹ năng</th><th>Hệ</th><th>Hệ số</th><th>MP</th><th>Hồi</th>"
            "<th>Tác dụng</th></tr></thead><tbody>" + rows + "</tbody></table></div>")
stabs = "".join(f'<button type="button" class="tab" data-g="sk" data-c="{c}">{l}</button>' for c, l in CLS)
spanes = "".join(f'<div class="ctab" data-g="sk" data-c="{c}"{" hidden" if i else ""}>{skill_table(c)}</div>' for i, (c, _) in enumerate(CLS))
cycle = " › ".join(el(e) for e in ["fire", "ice", "wind", "earth", "lightning", "fire"])
bylv = ", ".join(f"cấp {a}+ {el(e)}" for a, e in EL["by_level"])

# ---------- Vùng chuyển sinh ----------
rm = defaultdict(list)
for m in D["realm_monsters"]:
    rm[int(m["id"].split("_")[0][1:])].append(m)
rrows = ""
for mp in sorted(D["maps"], key=lambda m: m["realm"]):
    k = mp["realm"]; ms = sorted(rm[k], key=lambda m: m["level"])
    names = ", ".join(E(m["name"]) for m in ms)
    loot = min(rl["loot_max"], rl["loot_per_realm"] * ms[0]["rich"]) if ms else 0
    rrows += (f"<tr><td class=n>{k}</td><td><b>{E(mp['name'])}</b></td><td class=n>{mp['min_rebirths']}</td><td class=n>{ms[0]['level']}–{ms[-1]['level']}</td>"
              f"<td>{el(ms[0].get('element'))}</td><td class=n>×{n(round(ms[0]['mult'], 2))}</td><td class=n>+{pct(loot)}</td>"
              f"<td class=n>{pct(ms[0]['jewel_chance'])}</td><td>{names}</td></tr>")

# ---------- Vật phẩm khác ----------
def grp(title, ids):
    ids = [i for i in ids if i in IT]
    if not ids:
        return ""
    r = f"<tr class=grp><td colspan=3>{title} ({len(ids)})</td></tr>"
    for i in ids:
        v = IT[i]
        use = v.get("desc") or (f"hồi {pct(v['heal_pct'])} máu" if v.get("heal_pct") else f"hồi {pct(v['mana_pct'])} MP" if v.get("mana_pct") else "")
        r += f"<tr><td>{nm(v, True)}</td><td>{E(use)}</td><td class=n>{n(v.get('price', 0))}</td></tr>"
    return r
other = (grp("Bình máu", ["potion_s", "potion_m", "potion_l"]) + grp("Bình mana", ["mana_s", "mana_m", "mana_l"]) +
         grp("Món ăn", ["cha_ca", "banh_mi_ca", "banh_xeo_luon", "mam_co"]) +
         grp("Ngọc", ["jewel_bless", "jewel_soul", "jewel_chaos", "jewel_life"]) +
         grp("Vé và nguyên liệu sự kiện", ["ds_ticket", "bc_ticket", "cc_ticket", "devil_eye", "devil_key", "archangel_scroll", "blood_bone",
                                           "kundun_mark", "lost_map", "condor_feather"]) +
         grp("Nguyên liệu thu thập", ["herb", "herb_rare", "ore", "ore_rare", "fish_small", "fish_carp", "fish_eel", "fish_gold", "old_boot", "dragon_scale"]) +
         grp("Quà lễ hội", ["moon_cake", "pumpkin_candy", "gift_box", "lucky_apple"]))

page = open(os.path.join(os.path.dirname(__file__), "tpl.html"), encoding="utf-8").read()
for k, v in dict(OVERVIEW=overview, TABS=tabs, PANES=panes, TIERS=trows, JEW=jrows, WINGS=wrows, UPG=erows, EXC_W=exl("weapon"),
                 EXC_A=exl("armor"), ANC=anc_li, OPT=opt_li, LOOT=lrows, SLOTS=", ".join(slot_txt), STABS=stabs, SPANES=spanes,
                 CYCLE=cycle, BYLV=bylv, REALMS=rrows, OTHER=other,
                 SB=f"+{pct(sb['def_pct'])} thủ, +{pct(sb['atk_pct'])} công, +{sb['hp_per_tier']} máu × bậc bộ",
                 UPPCT=pct(R['upgrade']['bonus_pct']), ANNOUNCE=str(up['announce_from']), DOUBLE=str(up['double_from']),
                 LUCKUP=pct(ls['luck_upgrade']), LUCKMAX=pct(ls['luck_max_rate']), LUCKCRIT=pct(ls['luck_crit']), SKILLDMG=pct(ls['skill_dmg']),
                 LIFE=f"+{life['per_line']} mỗi dòng, tối đa {life['max_lines']} dòng, {pct(life['rate'])}",
                 EXCLINES=", ".join(f"{a} dòng {pct(b/sum(w for _, w in ex['lines']))}" for a, b in ex["lines"]),
                 EXCPRICE=n(ex['price_mult']), DMGRED=pct(ex['max_dmg_red']), REFL=pct(ex['max_reflect']),
                 ANCDEF=pct(anc['piece_def_pct']), ANCPRICE=n(anc['price_mult']), PERLINE=str(life['per_line']),
                 STRONG=pct(EL['strong']), WEAK=pct(EL['weak']), LOADOUT=str(R['tower_skills']['loadout']),
                 RMIN=str(rl['min_level']), RSTAT=str(rl['stat_level']), RMULT=n(rl['mult_per_realm']), RBOSS=n(rl['boss_mult']),
                 SELL=pct(R['shop']['sell_ratio'])).items():
    page = page.replace("{{" + k + "}}", v)
assert "{{" not in page, page[page.index("{{"):page.index("{{") + 40]
open(OUT, "w", encoding="utf-8").write(page)
json.dump(sorted(USED), open(OUT + ".files.json", "w"))
print(len(page), "bytes,", len(USED), "hình")

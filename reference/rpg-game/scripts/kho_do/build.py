"""Sinh trang "Kho Đồ Hắc Long" từ dữ liệu game (data.json do export.exs ghi) + bảng hình Pixel."""
import json, html, sys, os
from collections import defaultdict

D = json.load(open(sys.argv[1], encoding="utf-8"))
PIX = json.load(open(sys.argv[2], encoding="utf-8"))
OUT = sys.argv[3]
IT, R, CL = D["items"], D["rules"], D["classes"]
GEAR_SLOTS = {"weapon", "shield", "helm", "armor", "pants", "gloves", "boots", "ring", "pendant", "wing"}
SHOP = {i for i in D["shop"] if i in IT and (IT[i].get("slot") not in GEAR_SLOTS or (
    IT[i].get("sourceType") == "MU_ITEM_TXT" and IT[i].get("price", 0) > 0 and IT[i]["slot"] not in ("ring", "pendant")
    and not IT[i].get("alt") and (IT[i].get("level") or 1) <= D["rules"]["shop"]["smith_max_level"]))}
USED = set()
CLS = [("dk", "Kiếm Sĩ"), ("dw", "Phù Thủy"), ("elf", "Tiên Nữ"), ("mg", "Đấu Sĩ")]
ARMOR = ["helm", "armor", "pants", "gloves", "boots"]
E = html.escape


def n(x):
    if isinstance(x, float) and x.is_integer():
        x = int(x)
    return f"{x:,}" if isinstance(x, int) else str(x).replace(".", ",")


def pct(x, d=1):
    v = round(x * 100, d)
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
  Món phụ có công, thủ, cấp như món chính cùng bậc, chỉ khác tên, hình và yêu cầu chỉ số. 🛒: bán ở Thợ Rèn (chỉ món chính cấp ≤ {R['shop']['smith_max_level']});
  món phụ, nhẫn, dây chuyền và đồ cao hơn chỉ có từ quái, rương, sự kiện, chợ. Hình đồ trên trang là bộ <b>Pixel</b> trong game (CC0, Dungeon Crawl Stone Soup).</p>"""

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
                 f"<td class=n>×{n(k.get('mult') or R['skill_effects'].get(k.get('effect'), {}).get('mult', 1))}</td><td class=n>{k.get('mp', 0)}</td><td class=n>{k.get('cooldown', 0)}</td><td>{E(k.get('desc') or sdesc(k))}</td></tr>")
    for k in CL[c]["tower_skills"]:
        rows += (f"<tr><td>tháp {k['floor']}</td><td><b>{E(k['name'])}</b></td><td>{el(k.get('element'))}</td>"
                 f"<td class=n>×{n(k['mult'])}</td><td class=n>{k['mp']}</td><td class=n>{k['cooldown']}</td><td>{sdesc(k)}</td></tr>")
    return ("<div class=\"scroll\"><table><thead><tr><th>Mở</th><th>Kỹ năng</th><th>Hệ</th><th>Hệ số</th><th>MP</th><th>Hồi</th>"
            "<th>Tác dụng</th></tr></thead><tbody>" + rows + "</tbody></table></div>")
stabs = "".join(f'<button type="button" class="tab" data-g="sk" data-c="{c}">{l}</button>' for c, l in CLS)
spanes = "".join(f'<div class="ctab" data-g="sk" data-c="{c}"{" hidden" if i else ""}>{skill_table(c)}</div>' for i, (c, _) in enumerate(CLS))
cycle = " › ".join(el(e) for e in ["fire", "ice", "wind", "earth", "lightning", "fire"])
bylv = ", ".join(f"cấp {a}+ {el(e)}" for a, e in EL["by_level"])

# ---------- Chỉ số & chiến đấu ----------
C, MON, PK = R["combat"], R["monster"], R["pk"]
cr, cm, dg, hit = C["crit"], C["crit_mult"], C["dodge"], C["hit"]
def srow(name, how, use):
    return f"<tr><td><b>{name}</b></td><td>{how}</td><td>{use}</td></tr>"
stat_rows = "".join([
    srow("Tấn công", "Hệ số lớp theo Sức mạnh / Nhanh nhẹn / Năng lượng + công vũ khí và dây chuyền + ép + dòng cộng thêm; × (1 + thú cưng + món ăn + Đài Phúc Lành); × (1 + Excellent + đủ bộ + đồ Thần)",
         f"Mỗi đòn lấy ngẫu nhiên {pct(C['damage_spread'][0])}–{pct(C['damage_spread'][1])} tấn công. Kỹ năng nhân hệ số của kỹ năng; cánh, Kỹ năng vũ khí, sổ tay quái nhân thêm."),
    srow("Trúng quái", f"AR / (AR + cấp quái × {n(hit['monster_dr'])}), trong {pct(hit['min'])}–{pct(hit['max'])}; AR = cấp × {n(hit['level'])} + Nhanh nhẹn × {n(hit['agi'])} (+ Excellent)",
         "Chỉ khi đánh quái. Quái cấp cao hơn khó trúng hơn. Kỹ năng luôn trúng. Đánh người thì xem né của đối thủ."),
    srow("Phòng thủ", "Tổng thủ giáp, khiên, cánh, mũ, quần, găng, giày, nhẫn + ép + dòng cộng thêm; × thú / món ăn / Đài; × đủ bộ, đồ Thần",
         f"Sát thương nhận = đòn² / (đòn + thủ), không dưới {pct(C['soft_floor'])} đòn: đòn bằng thủ chỉ còn một nửa. Như nhau khi bị quái hay người đánh."),
    srow("Chí mạng", f"{pct(cr['base'])} + Nhanh nhẹn × {pct(cr['per_agi'], 2)} (tối đa {pct(cr['max'])}) + Excellent + May mắn vũ khí. Hệ số ×({n(cm['base'])} + Nhanh nhẹn × {n(cm['per_agi'])}), tối đa ×{n(cm['max'])}",
         f"Đòn thường và kỹ năng (đánh quái, Đồ sát, Đấu trường). PK cược: kỹ năng không chí mạng. Quái chí mạng {pct(MON['crit'])} ×{n(C['monster_crit_mult'])}."),
    srow("Né đòn", f"{pct(dg['base'])} + Nhanh nhẹn × {pct(dg['per_agi'], 2)} (tối đa {pct(dg['max'])}), × Excellent tỉ lệ phòng thủ, trần cuối {pct(dg['max_total'])}; đánh quái cộng buff né, tổng tối đa {pct(dg['max_with_buff'])}",
         "Né đòn thường của quái và của người. Không né được đòn đặc biệt của quái và kỹ năng của người."),
    srow("Cánh", f"Số gốc của cánh + {pct(C['wing_per_level'])} mỗi cấp ép",
         "+% sát thương mọi đòn và −% sát thương nhận, cả đánh quái lẫn đánh người. Dòng phụ: máu, MP, bỏ qua phòng thủ."),
    srow("Máu", "Hệ số lớp theo Thể lực và cấp + nhẫn máu + đủ bộ + đồ Thần + dòng cánh; × thú / món ăn / Đài; × Excellent", "Hết máu là gục."),
    srow("MP", "Hệ số lớp theo Năng lượng + dòng cánh; × Excellent",
         f"Kỹ năng tốn MP, tăng {pct(C['skill_mp_per_level'])} mỗi cấp nhân vật; hồi {pct(C['mp_regen'])} mỗi lượt và thêm theo Năng lượng."),
])
mode_rows = "".join([
    "<tr><td><b>Mình trúng</b></td><td>đòn thường theo tỉ lệ trúng quái; quái không né; kỹ năng luôn trúng</td><td>đòn thường theo né đối thủ; kỹ năng luôn trúng</td><td>đòn thường theo né đối thủ; kỹ năng không né được</td></tr>",
    "<tr><td><b>Mình bị đánh</b></td><td>né được đòn thường; đòn đặc biệt của quái không né được</td><td>né được đòn thường; kỹ năng của đối thủ không né được</td><td>né được đòn thường; kỹ năng không né được</td></tr>",
    "<tr><td><b>Chí mạng</b></td><td>của mình; quái theo số ở trên</td><td>hệ số thật của mỗi bên</td><td>chỉ đòn thường</td></tr>",
    "<tr><td><b>Giảm sát thương</b></td><td>thủ thế, hấp thụ cánh, Excellent</td><td>cả hai bên: hấp thụ cánh, Excellent, bỏ qua phòng thủ</td><td>như Đồ sát</td></tr>",
    f"<tr><td><b>Kỹ năng</b></td><td>bộ {R['tower_skills']['loadout']} kỹ năng mang vào trận</td><td>như đánh quái</td><td>mỗi {PK['special_every']} lượt kỹ năng lớp ×{n(PK['special_mult'])}</td></tr>",
    f"<tr><td><b>Thắng thua</b></td><td>hết máu</td><td>hết máu</td><td>hết máu; quá {PK['rounds']} lượt thì bên còn nhiều % máu hơn thắng</td></tr>",
])
mh, ma, md = MON["hp"], MON["atk"], MON["def"]
monster_line = (f"Quái cấp L: máu {n(mh['base'])} + {n(mh['level'])}L + {n(mh['level_sq'])}L², công {n(ma['base'])} + {n(ma['level'])}L, "
                f"thủ {n(md['base'])} + {n(md['level'])}L. Quái không né (mình trúng theo tỉ lệ trúng).")

# ---------- Sự kiện (RULES: devil_square, blood_castle, chaos_castle, kalima, castle_siege, raids, invasion; world_boss) ----------
LIB = D["library"]
MON = {m["id"]: m for m in LIB["monsters"]}
MAPN = {**{m["id"]: m["name"] for m in LIB["maps"]}, "home": "Nhà"}
def clock(every_h, off_min=0):
    t = [(off_min + every_h * 60 * i) % 1440 for i in range(24 // every_h)]
    s = sorted(t)
    f = lambda m: f"{m // 60}h{m % 60:02d}"
    return f"mỗi {every_h} giờ: {f(s[0])}, {f(s[1])} … {f(s[-1])}"
def items_txt(d):
    return ", ".join(f"{v} {E(IT[k]['name'])}" for k, v in d.items())
def tiers_txt(ts, key="level"):
    return "; ".join(f"cấp {t['from']}+ → quái cấp {t[key]}" + (f" (Kalima {t['n']})" if "n" in t else "") for t in ts)
def ticket_txt(ev):
    t = ev.get("ticket"); s = f"1 {E(IT[t]['name'])}" if t in IT else "—"
    if ev.get("ticket_price"):
        s += f" (Người Gác Tháp {n(ev['ticket_price'])} vàng"
        td = ev.get("ticket_drop") or {}
        if td.get("parts"):
            s += f"; hoặc ghép {' + '.join(E(IT[x]['name']) for x in td['parts'])} ở Máy Hỗn Nguyên, mảnh rơi {pct(td['chance'])} từ quái cấp {td['min_level']}+"
        elif td:
            s += f"; hoặc rơi {pct(td['chance'])} từ quái cấp {td['min_level']}+"
        s += ")"
    return s
ds, bc, cc, ka, cs, rd, inv = R["devil_square"], R["blood_castle"], R["chaos_castle"], R["kalima"], R["castle_siege"], R["raids"], R["invasion"]
WB = D["world_boss"]
WD = ["", "thứ Hai", "thứ Ba", "thứ Tư", "thứ Năm", "thứ Sáu", "thứ Bảy", "Chủ Nhật"]
def ev_row(name, when, who, entry, how, reward):
    rows = [("Khi nào", when), ("Ai vào", who), ("Vào bằng", entry), ("Diễn biến", how), ("Thưởng", reward)]
    return f'<div class="card ev"><h3>{name}</h3><dl>' + "".join(f"<dt>{k}</dt><dd>{v}</dd>" for k, v in rows) + "</dl></div>"
waves = " + ".join(str(w["count"]) + (" (trùm)" if w["boss"] else "") for w in ds["waves"])
top = "; ".join(f"hạng {i + 1}: {n(t['gold'])} vàng + {items_txt(t['items'])}" for i, t in enumerate(ds["top"]))
ka_mark = E(IT[ka["mark"]]["name"]) if ka["mark"] in IT else ka["mark"]
ev_rows = "".join([
    ev_row("Quảng Trường Quỷ", f"{clock(ds['every_hours'], ds['offset_hours'] * 60)}; vào trong {ds['entry_minutes']} phút, đánh {ds['run_minutes']} phút",
           f"cấp {ds['min_level']}+; {tiers_txt(ds['tiers'])}", ticket_txt(ds),
           f"{len(ds['waves'])} đợt quái ({waves}), quái mỗi đợt mạnh dần; điểm: quái {ds['score']['monster']}, trùm {ds['score']['boss']}",
           f"vàng, kinh nghiệm theo điểm; mỗi {ds['reward']['jewel_every']} điểm 1 ngọc; qua hết đợt được 1 món đồ ({pct(ds['reward']['clear_exc_chance'])} Excellent, {pct(ds['reward']['clear_anc_chance'])} Thần). Top ngày (thư lúc 0h): {top}"),
    ev_row("Lâu Đài Máu", f"{clock(bc['every_hours'], bc['offset_minutes'])}; vào trong {bc['entry_minutes']} phút, đánh {bc['run_minutes']} phút",
           f"cấp {bc['min_level']}+; {tiers_txt(bc['tiers'])}", ticket_txt(bc),
           f"hạ {bc['guards']} quái canh → phá {E(bc['gate']['name'])} (không đánh trả, máu ×{bc['gate']['hp_mult']}) → hạ {E(bc['boss']['name'])}",
           f"thắng: vàng, kinh nghiệm, {items_txt(bc['reward']['success']['items'])}, {bc['reward']['success']['jewels']} ngọc; không xong: thưởng theo số quái canh đã hạ"),
    ev_row("Hỗn Chiến Thành", f"{clock(cc['every_hours'], cc['offset_minutes'])}; vào trong {cc['entry_minutes']} phút, đánh {cc['run_minutes']} phút",
           f"cấp {cc['min_level']}+; quái quanh cấp trung bình người vào (±{cc['level_spread']})", ticket_txt(cc),
           f"{cc['total']} đối thủ (quái + người, ít nhất {cc['min_monsters']} quái); gục là bị loại, không mất vàng, không tên đỏ",
           f"người cuối cùng: {n(cc['reward']['winner']['gold'])} vàng + {items_txt(cc['reward']['winner']['items'])}; trụ tới hết giờ: {n(cc['reward']['survivor']['gold'])} vàng + {items_txt(cc['reward']['survivor']['items'])}; mỗi người hạ được +{n(cc['reward']['per_player_kill'])} vàng"),
    ev_row("Kalima", "lúc nào cũng vào được", f"cấp {ka['min_level']}+; {tiers_txt(ka['tiers'])}", ticket_txt(ka) + f" (ghép từ 5 {ka_mark}, rơi {pct(ka['mark_drop']['chance'])} từ quái cấp {ka['mark_drop']['min_level']}+)",
           f"bản đồ riêng {ka['run_minutes']} phút: hạ {ka['guards']} quái → {E(ka['boss']['name'])} xuất hiện",
           f"hạ {E(ka['boss']['name'])}: vàng, kinh nghiệm, {ka['reward']['success']['jewels']} ngọc, 1 món đồ ({pct(ka['reward']['success']['exc_chance'])} Excellent, {pct(ka['reward']['success']['anc_chance'])} Thần); không xong: theo số quái đã hạ"),
    ev_row("Công Thành Chiến", f"{WD[cs['weekday']]} {cs['hour']}h{cs['minute']:02d}, {cs['run_minutes']} phút",
           f"thành viên (cấp {cs['min_level']}+) của bang đã đăng ký và bang giữ thành", f"bang chủ / phó đăng ký ở Người Gác Tháp ({n(cs['register_gold'])} vàng)",
           f"giữ {E(cs['crown']['name'])} giữa thành (hạ được thì giữ, hiện lại sau {cs['crown']['respawn_s']} giây); đánh nhau không mất vàng, không tên đỏ",
           f"bang giữ Vương Miện lúc hết giờ là Chủ Thành tới trận sau; mỗi thành viên {n(cs['reward']['gold'])} vàng + {items_txt(cs['reward']['items'])}"),
] + [ev_row(f"{v['icon']} {E(v['name'])}", f"{clock(v['every_hours'], v['offset_minutes'])}, {v['minutes']} phút", "mọi người",
            "không cần", f"{v['leader']['count']} {E(v['leader']['name'])} (cấp + {v['leader']['level_bonus']}, sức ×{n(v['leader']['mult'])})" +
            (f" và {v['minion']['count']} {E(v['minion']['name'])}" if v.get("minion") else "") + f" ở {v['pick']} bản đồ ngẫu nhiên trong {len(v['maps'])} vùng chính",
            f"thưởng ×{v['reward_mult']}; con đầu đàn chắc chắn rơi ngọc, thêm " + ", ".join(f"{E(IT[k]['name'])} {pct(c)}" for k, c in v["drops"].items()))
   for v in rd.values() if isinstance(v, dict) and v.get("leader")] + [
    ev_row("✨ Quái Vàng", f"{clock(inv['every_hours'])}, {inv['minutes']} phút", "mọi người", "không cần",
           f"{sum(inv['maps'].values())} quái vàng ở {len(inv['maps'])} vùng chính (sức ×{n(inv['strength_mult'])}); hạ hết một bản đồ thì trùm vàng xuất hiện",
           f"thưởng ×{inv['reward_mult']}, quái vàng {pct(inv['jewel_chance'])} rơi ngọc, trùm vàng chắc chắn"),
    ev_row("🐉 Trùm thế giới", f"lần đầu {WB.get('first_after_minutes')} phút sau khi máy chủ chạy, rồi cứ {WB.get('every_minutes')} phút sau khi con trước gục / bay đi; ở {WB.get('duration_minutes')} phút",
           "mọi người, ở Tế Đàn", "không cần", f"cả máy chủ đánh chung một thanh máu ({n(WB.get('hp'))})",
           "chia thưởng theo phần sát thương; 3 người gây nhiều nhất thêm Vảy Cổ Long; đòn cuối thêm vàng; hết giờ chưa hạ thì không ai được"),
])
fest = "".join(f"<tr><td>{e['icon']} <b>{E(e['name'])}</b></td><td>{e['from']} → {e['to']}</td><td>{E(e['desc'])}</td><td>{E(IT[e['token']]['name']) if e.get('token') in IT else '—'}</td></tr>"
               for e in D["festivals"])

# ---------- Bản đồ và quái ----------
def mrow(m):
    lv = "—" if not m["min"] else (f"{m['min']}" if m["min"] == m["max"] else f"{m['min']}–{m['max']}")
    mons = ", ".join(E(MON[k]["name"]) for k in m["monsters"] if k in MON and not MON[k]["boss"])
    bk = [k for k in m["monsters"] if k in MON and MON[k]["boss"]] + ([m["boss"]] if m.get("boss") in MON and m["boss"] not in m["monsters"] else [])
    boss = ", ".join(f"<b>{E(MON[k]['name'])}</b>" for k in bk)
    # như client (travelCost): Làng, Nhà miễn phí; nơi khác base + per_level × cấp quái thấp nhất (không quái: 0)
    cost = "miễn phí" if m["id"] in R["travel"]["free"] else n(R["travel"]["base"] + R["travel"]["per_level"] * (m["min"] or 0))
    need = f"CS {m['cs']}, cấp {m['need']}+" if m.get("cs") else (f"cấp {m['min']}+" if m["min"] else "—")
    return f"<tr><td><b>{E(m['name'])}</b></td><td class=n>{lv}</td><td>{need}</td><td>{mons or ''}{(' · ' if mons else '') + 'trùm ' + boss if boss else ''}{'—' if not mons and not boss else ''}</td><td class=n>{cost}</td></tr>"
grp_maps = defaultdict(list)
for m in LIB["maps"]:
    if m["id"] == "tower":
        continue
    key = "Vùng đất chuyển sinh" if m.get("cs") else (m.get("zone") or "Làng, Tế Đàn")
    grp_maps[key].append(m)
order = sorted(grp_maps, key=lambda k: (k == "Vùng đất chuyển sinh", k == "Bản đồ phụ", min((x["min"] or 0) for x in grp_maps[k])))
map_rows = "".join(f"<tr class=grp><td colspan=5>{E(k)} ({len(grp_maps[k])})</td></tr>" + "".join(mrow(m) for m in sorted(grp_maps[k], key=lambda x: (x["min"] or 0, x["name"]))) for k in order)
bosses = sorted([m for m in LIB["monsters"] if m["boss"]], key=lambda m: m["level"])
boss_rows = "".join(f"<tr><td><b>{E(m['name'])}</b></td><td class=n>{m['level']}</td><td>{', '.join(E(w) for w in m['where'])}</td><td class=n>{n(m['hp'])}</td><td class=n>{n(m['atk'])} / {n(m['def'])}</td>"
                    f"<td>{E(m['special']['name']) + ' mỗi ' + str(m['special']['every']) + ' lượt' if m.get('special') else '—'}</td></tr>" for m in bosses)
br = R["boss_rewards"]; fkw = sum(w for _, w in br["first_kill_weights"])
boss_note = ("Hạ trùm vùng lần đầu: 1 món đồ hiếm đúng lớp (" + ", ".join(f"{a} dòng cộng thêm {pct(w / fkw)}" for a, w in br["first_kill_weights"]) +
            "); mỗi ngày lần đầu hạ trùm vùng: " + "; ".join(
                 f"vùng {d['from_zone'] + 1}" + (f"–{br['daily'][i + 1]['from_zone']}" if i + 1 < len(br['daily']) else " trở đi") + f" được {d['n']} {E(IT[d['item']]['name'])}"
                 for i, d in enumerate(br["daily"])) + ".")

# ---------- Tháp Vô Tận ----------
TW = R["tower"]
def tw_mult(f):
    return 1 + max(0, f - TW["harder_from"]) * TW["harder_per_floor"]
tower_rows = "".join(
    f"<tr><td class=n>{r['floor']}</td><td class=n>{r['floor']}</td><td class=n>×{n(round(tw_mult(r['floor']), 2))}</td>"
    f"<td class=n>{(str(TW['boss_monsters']) + ' + trùm') if r['floor'] % TW['boss_every'] == 0 else min(TW['max_monsters'], TW['monsters'] + TW['monsters_per_10'] * (r['floor'] // 10))}</td>"
    f"<td class=n>{n(r['gold'])}</td><td class=n>{n(r['xp'])}</td><td>{items_txt(r['items']) or '—'}{' + 1 ngọc (lần đầu)' if r['floor'] % D['jewels']['tower_every'] == 0 else ''}</td></tr>"
    for r in D["tower_rows"])

# ---------- PK, đồ sát ----------
SL, AR, GW, PKR = R["slay"], R["arena"], R["guild_war"], R["pk"]
pk_items = [
    ("Đồ sát", f"tấn công người khác trên bản đồ chung (không ở {', '.join(E(MAPN.get(x, x)) for x in SL['safe_maps'])}), cả hai từ cấp {SL['min_level']}. Người kia đang đánh quái vẫn bị đánh ngay (trận đánh quái bị cắt ngang, quái giữ máu); chỉ không đánh được người đang trong trận đồ sát khác, và mình phải không đang trong trận. Luân phiên lượt, mỗi lượt {SL['turn_s']} giây, quá giờ tự đánh thường. Thua (hết máu hoặc bỏ chạy) là gục như thường: mất {pct(R['character']['death_gold_loss'])} vàng đang mang, số vàng đó về tay người thắng."),
    ("Tên đỏ", f"thắng một người không tên đỏ thì bị tên đỏ {SL['red_s'] // 60} phút (cộng dồn). Người tên đỏ gục trong đồ sát mất vàng ×{SL['red_gold_mult']}. Hạ người tên đỏ thì không bị đỏ. Tự đánh tắt khi có người tên đỏ trên bản đồ."),
    ("Bảo vệ, giới hạn", f"vừa gục được bảo vệ {SL['protect_s']} giây (tự đi đồ sát thì mất bảo vệ); mỗi người đồ sát cùng một người tối đa {SL['per_target_hour']} lần trong 60 phút."),
    ("PK cược vàng", f"mời người khác cược từ {n(PKR['min'])} tới {n(PKR['max'])} vàng, tối đa {PKR['per_day']} trận mỗi ngày; hai bản sao chỉ số tự đánh (xem Chỉ số, chiến đấu), người thắng nhận tiền cược."),
    ("Đấu trường", f"đánh bản sao chỉ số người khác, tối đa {AR['per_day']} trận mỗi ngày, điểm xếp hạng kiểu Elo (K = {AR['elo_k']})."),
    ("Chiến bang", f"bang chủ / phó bang tuyên chiến bang khác (bang kia nhận trong {GW['answer_s']} giây), kéo dài {GW['minutes']} phút. Mỗi trận Đấu trường thắng thành viên bang địch +1 điểm (cùng một đối thủ tính tối đa {GW['same_target_max']} lần). Bang nhiều điểm thắng: quỹ +{n(GW['win_fund'])}, thành viên có điểm nhận {n(GW['win_gold'])} vàng qua thư; hai bang chờ {GW['rematch_hours']} giờ mới chiến lại."),
]
pk_li = "".join(f"<li><b>{k}</b>: {v}</li>" for k, v in pk_items)

# ---------- Lỗ hổng dữ liệu (OPEN_QUESTIONS KD-1): bậc thiếu bộ giáp / vũ khí chính theo lớp ----------
gaps = []
for c, label in CLS:
    for t in tiers:
        miss = [nm_ for s, nm_ in (("armor", "bộ giáp"), ("weapon", "vũ khí")) if not any(v["tier"] == t and not v.get("alt") for v in gear(c, s))]
        # bậc không lớp nào có bộ giáp (vd. bậc chỉ có vũ khí) thì không tính là thiếu
        miss = [x for x in miss if x != "bộ giáp" or any(v["tier"] == t and v["slot"] == "armor" for v in mu)]
        if miss and any(v["tier"] == t for v in mu if c in v.get("classes", [])):
            gaps.append(f"{label} bậc {t} chưa có {' và '.join(miss)} chính")
# Tiên Nữ dùng cung / nỏ: bậc có vũ khí chính nhưng không phải cung / nỏ
for t in tiers:
    w = [v for v in gear("elf", "weapon") if v["tier"] == t and not v.get("alt")]
    if w and not any(("Cung" in v["name"] or "Nỏ" in v["name"]) for v in w):
        gaps.append(f"Tiên Nữ bậc {t} chưa có cung / nỏ chính (đang là {', '.join(v['name'] for v in w)})")
gap_note = ("<p class=\"note\">Dữ liệu còn thiếu, đang chờ chọn thêm món: " + "; ".join(gaps) + ".</p>") if gaps else ""

# ---------- Quy tắc chi tiết ----------
UPR, LS, JW = R["upgrade"], R["luck_skill"], D["jewels"]
max_step = max(st["rate"] for st in D["upgrade"]["steps"] if st["rate"] < 1)
luck_real = min(LS["luck_max_rate"], max_step + LS["luck_upgrade"])
jw_tot = sum(JW["weights"].values())
jewel_src = ("Ngọc rơi: quái từ cấp " + str(JW["monster_level"]) + " " + pct(JW["monster_chance"]) + " mỗi con, trùm " + pct(JW["boss_chance"]) +
             ", Tháp Vô Tận mỗi " + str(JW["tower_every"]) + " tầng, rương, sự kiện; loại ngọc: " +
             ", ".join(f"{E(IT[k]['name'])} {pct(w / jw_tot)}" for k, w in JW["weights"].items()) + ".")
def crow(c, label):
    d = CL[c]["derived"]
    f = lambda part: " + ".join(f"{n(v)} × {dict(str='Sức mạnh', agi='Nhanh nhẹn', vit='Thể lực', ene='Năng lượng', level='cấp').get(k, k)}" if k != "base" else n(v) for k, v in part.items())
    b = CL[c]["base"]
    return (f"<tr><td><b>{label}</b></td><td class=n>{b['str']} / {b['agi']} / {b['vit']} / {b['ene']}</td><td class=n>{CL[c]['points']}</td>"
            f"<td>{f(d['atk'])}</td><td>{f(d['def'])}</td><td>{f(d['hp'])}</td><td>{f(d['mp'])}</td></tr>")
class_rows = "".join(crow(c, l) for c, l in CLS)
def chrow(r):
    need = " + ".join(f"{v} {E(IT[k]['name'])}" for k, v in r.get("items", {}).items())
    if r.get("gear"):
        need = f"1 món ({', '.join(r['gear'].get('slots', []))}) +{r['gear'].get('min_up', 0)}" + (" + " + need if need else "")
    rate = pct(r["rate"]) + (f", +{pct(r['per_up'])} mỗi cấp ép trên +{r['gear'].get('min_up', 0)}, tối đa {pct(r['max_rate'])}" if r.get("per_up") else "")
    return f"<tr><td><b>{E(r['name'])}</b></td><td>{need}</td><td class=n>{n(r['gold'])}</td><td>{rate}</td></tr>"
chaos_rows = "".join(chrow(r) for r in D["chaos"])
bm = R["bestiary"]["marks"]
dq = lambda e: R["skill_effects"][e]
rule_items = [
    ("Cấp quái khi tính trúng", "cấp hiện trên quái (vùng chuyển sinh 142–150 là dùng số đó), không phải cấp tính chỉ số."),
    ("Ép cánh", f"{pct(C['wing_per_level'])} mỗi cấp tính theo cột \"Tính như\" (+11 tính 13 cấp), cộng cả % sát thương lẫn % giảm nhận; không có trần tổng."),
    ("MP kỹ năng", f"số MP trong bảng là ở cấp 1; tốn = MP × (1 + {n(C['skill_mp_per_level'])} × (cấp − 1)), cộng thẳng, không lũy thừa."),
    ("Cột \"Hồi\" (kỹ năng)", "số lượt phải chờ trước khi dùng lại kỹ năng đó (hồi chiêu)."),
    ("Kỹ năng nhiều đòn", "hệ số là tổng, chia đều cho các đòn; chí mạng tính một lần cho cả chiêu, phòng thủ trừ riêng từng đòn."),
    ("Độc, đốt", f"mỗi lượt quái mất một phần sát thương vừa gây (Kiếm Độc Hỏa {pct(dq('venom')['power'])} trong {dq('venom')['turns']} lượt; kỹ năng Tháp ghi ở cột Tác dụng)."),
    ("Phòng thủ của quái", "dùng cùng công thức giảm sát thương: đòn² / (đòn + thủ quái), không dưới " + pct(C["soft_floor"]) + " đòn."),
    ("Đòn đặc biệt của quái", "trùm và một số quái có chiêu riêng, dùng mỗi N lượt (màn trận ghi \"tên chiêu mỗi N lượt\"): mạnh hơn đòn thường, không né được, không chí mạng."),
    ("Sổ tay quái", "hạ đủ " + " / ".join(f"{m['kills']} con (+{pct(m['bonus'])})" for m in bm) + " một loại quái thì đánh loại đó mạnh hơn."),
    ("Đồ rơi theo cấp", "món rơi lấy trong 2 mức cấp cao nhất không quá cấp quái của ô đó, đúng lớp người hạ; \"bộ giáp\" là một món ngẫu nhiên trong mũ, giáp, quần, găng, giày (Đấu Sĩ không có mũ); \"trang sức\" là nhẫn hoặc dây chuyền."),
    ("Đủ bộ, đồ Thần cùng bộ", "đủ bộ tính các món cùng tên bộ, cùng bậc; đồ Thần đếm các món Thần cùng tên bộ. Đấu Sĩ đủ bộ là 4 món (không mũ), cho cả thưởng đủ bộ lẫn mức \"đủ bộ\" của đồ Thần."),
    ("Phí vàng ép", f"max(giá món, {n(UPR['cost_min_price'])}) × {pct(UPR['cost_pct'])} × cấp ép lên."),
    ("May mắn khi ép", f"cộng {pct(LS['luck_upgrade'])}, trần {pct(LS['luck_max_rate'])}; với bảng ép hiện tại cao nhất là {pct(luck_real)}."),
    ("Thú nuôi", f"ô thú nuôi đeo thú cưng (mua, hoặc thuần hóa loại quái đã hạ {R['pets']['tame_kills']} con); thú cộng % chỉ số và có lúc cắn quái."),
    ("Đài Phúc Lành", f"chạm vào: phúc lành của bản đồ ({R['blessing']['battles']} trận, +{pct(R['blessing']['pct'])} kinh nghiệm / vàng / công / thủ / máu tùy đài) và thành điểm hồi sinh khi gục."),
]
rule_li = "".join(f"<li><b>{k}</b>: {v}</li>" for k, v in rule_items)

# ---------- Vùng chuyển sinh ----------
rm = defaultdict(list)
for m in D["realm_monsters"]:
    rm[int(m["id"].split("_")[0][1:])].append(m)
rrows = ""
for mp in sorted(D["maps"], key=lambda m: m["realm"]):
    k = mp["realm"]; ms = sorted(rm[k], key=lambda m: m["level"])
    names = ", ".join(E(m["name"]) for m in ms)
    raw = rl["loot_per_realm"] * ms[0]["rich"] if ms else 0
    loot = min(rl["loot_max"], raw)
    rrows += (f"<tr><td class=n>{k}</td><td><b>{E(mp['name'])}</b></td><td class=n>{mp['min_rebirths']}</td><td class=n>{ms[0]['level']}–{ms[-1]['level']}</td>"
              f"<td>{el(ms[0].get('element'))}</td><td class=n>×{n(round(ms[0]['mult'], 2))} / ×{n(round(ms[0].get('atk_mult', ms[0]['mult']), 2))}</td><td class=n>+{pct(loot)}{' (trần)' if raw > rl['loot_max'] + 1e-9 else ''}</td>"
              f"<td class=n>{pct(ms[0]['jewel_chance'])}</td><td>{names}</td></tr>")

# ---------- Vật phẩm khác ----------
# nơi mua: cửa hàng (giá gốc; bình thuốc tăng theo cấp nhân vật), vé ở Người Gác Tháp (RULES.<sự kiện>.ticket_price)
TICKET = {v["ticket"]: v["ticket_price"] for v in R.values() if isinstance(v, dict) and v.get("ticket") and v.get("ticket_price")}
def buy_at(i, v):
    if i in TICKET:
        return f"Người Gác Tháp: {n(TICKET[i])}"
    if i in D["shop"] and v.get("price", 0) > 0:
        return f"Cửa hàng: {n(v['price'])}" + (" + theo cấp" if i.startswith(("potion_", "mana_")) else "")
    return "—"
def grp(title, ids):
    ids = [i for i in ids if i in IT]
    if not ids:
        return ""
    r = f"<tr class=grp><td colspan=4>{title} ({len(ids)})</td></tr>"
    for i in ids:
        v = IT[i]
        use = v.get("desc") or (f"hồi {pct(v['heal_pct'])} máu" if v.get("heal_pct") else f"hồi {pct(v['mana_pct'])} MP" if v.get("mana_pct") else "")
        r += f"<tr><td>{nm(v, True)}</td><td>{E(use)}</td><td>{buy_at(i, v)}</td><td class=n>{n(v.get('sell') or 0) if v.get('sell') else '—'}</td></tr>"
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
                 CYCLE=cycle, BYLV=bylv, REALMS=rrows, OTHER=other, STATROWS=stat_rows, MODEROWS=mode_rows, MONSTER=monster_line, RULELI=rule_li, GAPS=gap_note, EVROWS=ev_rows, FEST=fest, MAPROWS=map_rows, BOSSROWS=boss_rows, BOSSNOTE=boss_note, TOWERROWS=tower_rows, PKLI=pk_li, TWHARD=str(TW['harder_from']), TWPER=pct(TW['harder_per_floor']), TWBOSS=str(TW['boss_every']), TWELITE=n(TW['elite_mult']), TWOFF=str(TW['level_offset']), TRAVEL=f"{R['travel']['base']} + {R['travel']['per_level']} × cấp quái thấp nhất", CLASSROWS=class_rows, CHAOSROWS=chaos_rows, JEWELSRC=jewel_src, POTLV=pct(R['shop']['potion_price_per_level']), RLOOT=pct(rl['loot_per_realm']), RLOOTMAX=pct(rl['loot_max']), LUCKREAL=pct(luck_real), COSTMIN=n(UPR['cost_min_price']), COSTPCT=pct(UPR['cost_pct']),
                 SB=f"+{pct(sb['def_pct'])} thủ, +{pct(sb['atk_pct'])} công, +{sb['hp_per_tier']} máu × bậc bộ",
                 UPPCT=pct(R['upgrade']['bonus_pct']), ANNOUNCE=str(up['announce_from']), DOUBLE=str(up['double_from']),
                 LUCKUP=pct(ls['luck_upgrade']), LUCKMAX=pct(ls['luck_max_rate']), LUCKCRIT=pct(ls['luck_crit']), SKILLDMG=pct(ls['skill_dmg']),
                 LIFE=f"{pct(life['per_line_pct'])} công / thủ gốc của món (ít nhất +{life['per_line']}) mỗi dòng, tối đa {life['max_lines']} dòng, {pct(life['rate'])}",
                 EXCLINES=", ".join(f"{a} dòng {pct(b/sum(w for _, w in ex['lines']))}" for a, b in ex["lines"]),
                 EXCPRICE=n(ex['price_mult']), DMGRED=pct(ex['max_dmg_red']), REFL=pct(ex['max_reflect']),
                 ANCDEF=pct(anc['piece_def_pct']), ANCPRICE=n(anc['price_mult']), PERLINE=f"{pct(life['per_line_pct'])} công / thủ gốc của món (ít nhất +{life['per_line']})",
                 STRONG=pct(EL['strong']), WEAK=pct(EL['weak']), LOADOUT=str(R['tower_skills']['loadout']),
                 RMIN=str(rl['min_level']), RSTAT=str(rl['stat_level']), RMULT=n(rl['mult_per_realm']), RBOSS=n(rl['boss_mult']),
                 SELL=pct(R['shop']['sell_ratio'])).items():
    page = page.replace("{{" + k + "}}", v)
assert "{{" not in page, page[page.index("{{"):page.index("{{") + 40]
open(OUT, "w", encoding="utf-8").write(page)
json.dump(sorted(USED), open(OUT + ".files.json", "w"))
print(len(page), "bytes,", len(USED), "hình")

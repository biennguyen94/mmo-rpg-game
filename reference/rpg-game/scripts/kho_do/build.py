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
    # vũ khí 2 tay (cung, nỏ, món rộng 2 ô trong Item.txt): không cầm khiên (B-41)
    if it.get("hands") == 2:
        name += ' <span class="hand2" title="Vũ khí 2 tay: không cầm khiên">2 tay</span>'
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
        # công bậc = công vũ khí 1 tay; vũ khí 2 tay mạnh hơn theo Item.txt (B-41)
        one = [v for v in w if v.get("hands") != 2]
        two = [v for v in w if v.get("hands") == 2]
        base = [v for v in one if not v.get("alt")] or one or [v for v in w if not v.get("alt")] or w
        atk = ""
        if base and one:
            lo = round(sum(v["atkMin"] for v in base) / len(base)); hi = round(sum(v["atkMax"] for v in base) / len(base))
            atk = f"{round((lo+hi)/2)} ({lo}~{hi})"
        if two:
            a2 = sorted(v["atk"] for v in two)
            atk += ("<br>" if atk else "") + f'<span class="muted">2 tay {a2[0]}{"–" + str(a2[-1]) if a2[-1] != a2[0] else ""}</span>'
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

# ép cánh theo bậc (RULES.wing_upgrade, như Engine.wing_up/3)
WU = R["wing_upgrade"]
def wing_up(key, tier, lv):
    t = WU[key]; i = min(max(tier, 1), len(t["per_level"])) - 1
    return t["per_level"][i] * min(lv, 9) + (t["jump10"][i] if lv >= 10 else 0) + (t["jump11"][i] if lv >= 11 else 0)
WLV = [0, 6, 9, 10, 11]
wuprows = ""
for t in sorted({w["tier"] for w in wings}):
    w0 = [w for w in wings if w["tier"] == t][0]
    dm = " / ".join(pct(w0["dmg"] + wing_up("dmg", t, l)) for l in WLV)
    ab = " / ".join(pct(min(WU["absorb"]["max"], w0["absorb"] + wing_up("absorb", t, l))) for l in WLV)
    wuprows += f"<tr><td class=n>{t}</td><td class=n>+{dm}</td><td class=n>−{ab}</td></tr>"

# ---------- Ép ----------
up = D["upgrade"]
FAIL = {None: "—", "down": "tụt 1 cấp", "reset": "<span class=bad>về +0</span>", "destroy": "<span class=bad>vỡ đồ</span>"}
AT = {"smith": "Thợ Rèn", "chaos": "Máy Hỗn Nguyên"}
erows = ""
ls0 = R["luck_skill"]
def luck_txt(s):
    return f" (May mắn {pct(min(ls0['luck_max_rate'], s['rate'] + s['luck']))})" if s.get("luck") else ""
for s in up["steps"]:
    lv = s["level"]
    eff = f"{n(s['eff'])} ({pct(s['eff'] * R['upgrade']['bonus_pct'], 0)})"
    need = " + ".join(f"{k2} {IT[k]['name']}" for k, k2 in s["items"].items())
    erows += (f"<tr><td class=n>+{lv}</td><td>{AT.get(s['at'], s['at'])}</td><td>vàng + {need}</td><td class=n>{pct(s['rate'])}{luck_txt(s)}</td>"
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
def mastery_note():
    sm = R["skill_mastery"]
    br = ", ".join(f"cấp {lv}: {c['cost']} Bí Kíp hoặc {c['alt']} Ngọc Tâm Linh" for lv, c in sorted(sm["break"].items(), key=lambda kv: int(kv[0])))
    need = " / ".join(f"{x:,}".replace(",", ".") for x in sm["need"])
    return E(f"Thông thạo: mỗi kỹ năng có cấp 1–{sm['max']}; số trong bảng là của cấp {sm['max']}. "
             f"Cấp 1 gây {pct(sm['mult_min'])} hệ số, mỗi cấp tăng đều tới 100 %; dưới cấp {sm['mp_level']} tốn MP ×{n(sm['mp_low'])}, "
             f"dưới cấp {sm['cd_level']} hồi chiêu +{sm['cd_low']} lượt, dưới cấp {sm['max']} tác dụng phụ (hồi máu, choáng, buff, độc…) ×{n(sm['effect_low'])}. "
             f"Luyện: mỗi lần dùng với quái +{sm['points']} điểm (tự đánh +{sm['points_auto']}), trùm / tinh anh ×{sm['boss_mult']}, quái thấp hơn quá {sm['level_gap']} cấp không tính, đánh người không tính. "
             f"Tổng điểm lên cấp 2…{sm['max']}: {need}. Đột phá: {br}. "
             f"Bí Kíp: lần đầu hạ mỗi trùm vùng / chúa tể vùng chuyển sinh chắc chắn {sm['drop']['first_boss']} cuốn, Tháp Vô Tận mỗi {sm['drop']['tower_every']} tầng vượt lần đầu 1 cuốn; rơi thêm: trùm hạ lại {pct(sm['drop']['boss'])}, quái tinh anh {pct(sm['drop']['elite'])}, trùm thế giới {pct(sm['drop']['world'])}. "
             f"Nhân vật có trước tính năng: kỹ năng đang có đã ở cấp {sm['max']}.")

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
    if k.get("stun"): p.append(f"{pct(k['stun'])} làm quái mất lượt (người: {pct(k['stun'] * R['pvp']['stun_mult'])})")
    if k.get("buff"): b = k["buff"]; p.append(BUFF.get(b["id"], b["id"]).format(pct(b["power"])) + f" ({b['turns']} lượt)")
    if k.get("debuff"): b = k["debuff"]; p.append(DEBUFF.get(b["id"], b["id"]).format(pct(b["power"])) + f" ({b['turns']} lượt)")
    return ", ".join(p) or "đòn mạnh"
# kỹ năng lớp: mô tả lấy từ RULES.skill_effects (số cấp tối đa), như client (ui.js skillDesc)
def cdesc(k):
    e = R["skill_effects"].get(k.get("effect") or k["id"])
    if not e: return k.get("desc") or ""
    p = []
    if e.get("def_mult") is not None: p.append(f"xuyên {pct(1 - e['def_mult'])} giáp")
    if e.get("always_crit"): p.append("chắc chí mạng")
    eff = k.get("effect") or k["id"]
    pw, t = e.get("power", 0), e.get("turns")
    if eff == "holy": p.append(f"hồi {pct(e['heal'])} máu")
    elif eff == "stun_bash": p.append(f"làm quái choáng mất lượt (trùm {pct(e['boss_resist'])} kháng; người: {pct(R['pvp']['stun_mult'])})")
    elif eff == "war_cry": p.append(f"cuồng nộ +{pct(pw)} công ({t} lượt)")
    elif eff == "venom": p.append(f"{'đốt' if k.get('element') == 'fire' else 'độc'}: mỗi lượt {pct(pw)} sát thương vừa gây ({t} lượt)")
    elif eff == "shadow_step": p.append(f"né +{pct(pw)} ({t} lượt)")
    elif eff == "guard": p.append(f"thủ thế −{pct(pw)} sát thương nhận ({t} lượt)")
    elif eff == "judgement": p.append(f"suy yếu quái −{pct(pw)} công ({t} lượt)")
    return ", ".join(p) or "đòn mạnh"

# hệ số cấp thông thạo 1 → tối đa
def mrange(m):
    return f"×{n(round(m * R['skill_mastery']['mult_min'], 2))} → ×{n(m)}"

def skill_table(c):
    rows = ""
    for k in CL[c].get("skills", []):
        rows += (f"<tr><td>cấp {k.get('level', 1)}</td><td><b>{E(k['name'])}</b></td><td>{el(k.get('element'))}</td>"
                 f"<td class=n>{mrange(k.get('mult') or R['skill_effects'].get(k.get('effect'), {}).get('mult', 1))}</td><td class=n>{k.get('mp', 0)}</td><td class=n>{k.get('cooldown', 0)}</td><td>{E(cdesc(k))}</td></tr>")
    for k in CL[c]["tower_skills"]:
        rows += (f"<tr><td>tháp {k['floor']}</td><td><b>{E(k['name'])}</b></td><td>{el(k.get('element'))}</td>"
                 f"<td class=n>{mrange(k['mult'])}</td><td class=n>{k['mp']}</td><td class=n>{k['cooldown']}</td><td>{sdesc(k)}</td></tr>")
    return ("<div class=\"scroll\"><table><thead><tr><th>Mở</th><th>Kỹ năng</th><th>Hệ</th><th>Hệ số (cấp 1 → 10)</th><th>MP</th><th>Hồi</th>"
            "<th>Tác dụng</th></tr></thead><tbody>" + rows + "</tbody></table></div>")
stabs = "".join(f'<button type="button" class="tab" data-g="sk" data-c="{c}">{l}</button>' for c, l in CLS)
spanes = "".join(f'<div class="ctab" data-g="sk" data-c="{c}"{" hidden" if i else ""}>{skill_table(c)}</div>' for i, (c, _) in enumerate(CLS))
cycle = " › ".join(el(e) for e in ["fire", "ice", "wind", "earth", "lightning", "fire"])
bylv = ", ".join(f"cấp {a}+ {el(e)}" for a, e in EL["by_level"])

# ---------- Chỉ số & chiến đấu ----------
C, MON, PK, PV = R["combat"], R["monster"], R["pk"], R["pvp"]
CLN = {"dk": "Kiếm Sĩ", "dw": "Phù Thủy", "elf": "Tiên Nữ", "mg": "Đấu Sĩ"}
pv_cls = ", ".join(f"{CLN.get(k, k)} ×{n(v)}" for k, v in PV.get("class_taken", {}).items())
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
         f"Đòn thường và kỹ năng. Đánh người: tỉ lệ ×{n(PV['crit_rate_mult'])}, phần cộng thêm của hệ số ×{n(PV['crit_bonus_mult'])}. Quái chí mạng {pct(MON['crit'])} ×{n(C['monster_crit_mult'])}."),
    srow("Né đòn", f"{pct(dg['base'])} + Nhanh nhẹn × {pct(dg['per_agi'], 2)} (tối đa {pct(dg['max'])}), × Excellent tỉ lệ phòng thủ, trần cuối {pct(dg['max_total'])}; đánh quái cộng buff né, tổng tối đa {pct(dg['max_with_buff'])}",
         f"Né đòn thường của quái và của người (đánh người: né ×{n(PV['dodge_mult'])}). Không né được đòn đặc biệt của quái và kỹ năng của người."),
    srow("Cánh", f"Số gốc của cánh + phần ép theo bậc cánh (mục Cánh); hấp thụ tối đa {pct(WU['absorb']['max'])}",
         "+% sát thương mọi đòn và −% sát thương nhận, cả đánh quái lẫn đánh người. Dòng phụ: máu, MP, bỏ qua phòng thủ."),
    srow("Máu", "Hệ số lớp theo Thể lực và cấp + nhẫn máu + đủ bộ + đồ Thần + dòng cánh; × thú / món ăn / Đài; × Excellent", "Hết máu là gục."),
    srow("MP", "Hệ số lớp theo Năng lượng + dòng cánh; × Excellent",
         f"Kỹ năng tốn MP, tăng {pct(C['skill_mp_per_level'])} mỗi cấp nhân vật; hồi {pct(C['mp_regen'])} mỗi lượt và thêm theo Năng lượng."),
])
mode_rows = "".join([
    f"<tr><td><b>Sát thương</b></td><td>đầy đủ</td><td colspan=2>mọi sát thương lên người (đòn thường, kỹ năng, thú cắn, độc) ×{n(PV['dmg_mult'])}, nhân thêm theo lớp người bị đánh: {pv_cls}</td></tr>",
    "<tr><td><b>Mình trúng</b></td><td>đòn thường theo tỉ lệ trúng quái; quái không né; kỹ năng luôn trúng</td><td>đòn thường theo né đối thủ; kỹ năng luôn trúng</td><td>đòn thường theo né đối thủ; kỹ năng không né được</td></tr>",
    "<tr><td><b>Mình bị đánh</b></td><td>né được đòn thường; đòn đặc biệt của quái không né được</td><td>né được đòn thường; kỹ năng của đối thủ không né được</td><td>né được đòn thường; kỹ năng không né được</td></tr>",
    f"<tr><td><b>Chí mạng</b></td><td>của mình; quái theo số ở trên</td><td colspan=2>tỉ lệ ×{n(PV['crit_rate_mult'])}, phần cộng thêm của hệ số ×{n(PV['crit_bonus_mult'])} (thu nhỏ theo tỉ lệ, không chặn trần)</td></tr>",
    f"<tr><td><b>Choáng</b></td><td>quái mất lượt</td><td colspan=2>tỉ lệ choáng ×{n(PV['stun_mult'])} (mọi kỹ năng, cả Thủy Long Ba); bị choáng mất một lượt; vừa thoát choáng thì kháng {PV['stun_immune']} lượt</td></tr>",
    "<tr><td><b>Hiệu ứng lên nhau</b></td><td>choáng, suy yếu, độc lên quái; buff lên mình</td><td>choáng, suy yếu, độc / bỏng mình gây chuyển sang người bị đánh (độc trừ máu đầu lượt của họ); thủ thế, khiên, Bất Tử, Ảnh Bộ, thú cưng che chắn, Long Vương Hồi Sinh của người bị đánh vẫn đỡ đòn; mỗi trận chỉ được cứu một lần (Bất Tử hoặc Long Vương Hồi Sinh, cái nào trước), dùng lại Bất Tử không cứu thêm</td><td>như Đồ sát</td></tr>",
    f"<tr><td><b>Bình máu</b></td><td>uống được mọi lượt</td><td>hồi ×{n(PV['potion_mult'])}; mỗi {PV['potion_cd']} lượt của mình uống được một lần (mất lượt như đánh quái)</td><td>không dùng (tự đánh)</td></tr>",
    "<tr><td><b>Giảm sát thương</b></td><td>thủ thế, khiên, thú che chắn, hấp thụ cánh, Excellent</td><td>cả hai bên: hấp thụ cánh, Excellent, bỏ qua phòng thủ; thêm thủ thế / khiên / thú của người bị đánh</td><td>như Đồ sát</td></tr>",
    "<tr><td><b>Phản sát thương (Excellent)</b></td><td>quái mất phần phản lại nhưng không chết vì phản đòn (còn ít nhất 1 máu)</td><td>Đồ sát: người đánh mất phần phản lại, còn ít nhất 1 máu; Đấu trường: phản đòn hạ được đối thủ, cả hai chiều (Long Vương Hồi Sinh vẫn cứu)</td><td>người đánh mất phần phản lại, còn ít nhất 1 máu</td></tr>",
    f"<tr><td><b>Kỹ năng</b></td><td>bộ {R['tower_skills']['loadout']} kỹ năng mang vào trận</td><td>như đánh quái; đối thủ Đấu trường (máy) dùng kỹ năng mạnh nhất, thú, buff, hồi máu như người</td><td>mỗi bên tự dùng kỹ năng mạnh nhất còn dùng được</td></tr>",
    f"<tr><td><b>Thắng thua</b></td><td>hết máu</td><td>hết máu; Đồ sát: luân phiên lượt, người tấn công đi trước; Đấu trường: cả hai cùng gục thì bên bị đánh lố ít hơn thắng</td><td>hai bên ra đòn cùng lúc; cùng gục thì bên bị đánh lố ít hơn thắng; quá {PK['rounds']} lượt thì bên còn nhiều % máu hơn thắng</td></tr>",
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
    ("Đồ sát", f"tấn công người khác trên bản đồ chung (không ở {', '.join(E(MAPN.get(x, x)) for x in SL['safe_maps'])}), cả hai từ cấp {SL['min_level']}. Người kia đang đánh quái vẫn bị đánh ngay (trận đánh quái bị cắt ngang, quái giữ máu); chỉ không đánh được người đang trong trận đồ sát khác, và mình phải không đang trong trận. Luân phiên lượt, mỗi lượt {SL['turn_s']} giây, quá giờ server ra đòn thay bằng kỹ năng mạnh nhất còn dùng được. Thua (hết máu hoặc bỏ chạy) là gục như thường: mất {pct(R['character']['death_gold_loss'])} vàng đang mang, số vàng đó về tay người thắng."),
    ("Tên đỏ", f"thắng một người không tên đỏ thì bị tên đỏ {SL['red_s'] // 60} phút (cộng dồn). Người tên đỏ gục trong đồ sát mất vàng ×{SL['red_gold_mult']}. Hạ người tên đỏ thì không bị đỏ. Tự đánh tắt khi có người tên đỏ trên bản đồ."),
    ("Bảo vệ, giới hạn", f"vừa gục được bảo vệ {SL['protect_s']} giây (tự đi đồ sát thì mất bảo vệ); mỗi người đồ sát cùng một người tối đa {SL['per_target_hour']} lần trong 60 phút."),
    ("PK cược vàng", f"mời người khác cược từ {n(PKR['min'])} tới {n(PKR['max'])} vàng, tối đa {PKR['per_day']} trận mỗi ngày; hai bản sao chỉ số tự đánh (xem Chỉ số, chiến đấu), người thắng nhận tiền cược."),
    ("Đấu trường", f"đánh người khác do máy điều khiển (kỹ năng, thú cưng, buff, hồi máu của chính người đó), tối đa {AR['per_day']} trận mỗi ngày, điểm xếp hạng kiểu Elo (K = {AR['elo_k']})."),
    ("Chiến bang", f"bang chủ / phó bang tuyên chiến bang khác (bang kia nhận trong {GW['answer_s']} giây), kéo dài {GW['minutes']} phút. Mỗi trận Đấu trường thắng thành viên bang địch +1 điểm (cùng một đối thủ tính tối đa {GW['same_target_max']} lần). Bang nhiều điểm thắng: quỹ +{n(GW['win_fund'])}, thành viên có điểm nhận {n(GW['win_gold'])} vàng qua thư; hai bang chờ {GW['rematch_hours']} giờ mới chiến lại."),
]
# ---------- Thú cưng ----------
PR = R["pets"]
# thú hiếm (Long Vương): không bán, câu được ở Hồ Long Vương (RULES.fishing.dragon), có kỹ năng 3 ở skill3_level
DRG = R["fishing"]["dragon"]
def pet_price(pt):
    if not pt.get("rare"):
        return n(pt["price"])
    _k = 1 + DRG['long_khi_max'] / DRG['long_khi_div']
    return (f"🎣 câu ở {E(D['lake']['name'])} (cấp {D['lake']['min_level']}+) khi Ngài nổi (mỗi giờ một lần, {DRG['stay'] // 60} phút): "
            f"thả trúng ô Ngài 1/{n(round(1 / DRG['chance']))} mỗi lần, đầy Long Khí + Mồi Rồng 1/{n(round(1 / (DRG['chance'] * _k * DRG['bait_mult'])))}")
def pet_sk2(pt):
    s2 = f"{E(pt['skill2']['name'])}: {E(pt['skill2']['desc'])}"
    if pt.get("skill3"):
        s2 += f"<br><b>Cấp {PR['skill3_level']}</b> {E(pt['skill3']['name'])}: {E(pt['skill3']['desc'])}"
    return s2
pet_rows = "".join(
    f"<tr><td><b>{E(pt['name'])}</b></td><td class=n>{pet_price(pt)}</td><td>{E(pt['desc'])}</td><td class=n>{pct(pt['bite'])}</td>"
    f"<td>{E(pt['skill']['name'])}: {E(pt['skill']['desc'])}</td><td>{pet_sk2(pt)}</td></tr>"
    for pt in sorted(D["pets"], key=lambda x: (x.get("rare", False), x["price"])))
pet_rule = (f"Cắn: {pct(PR['bite_chance'])} số lượt (+{pct(PR['bite_chance_per_level'])} mỗi cấp), mỗi lần bằng sức cắn × đòn thường (+{pct(PR['bite_power_per_level'])} mỗi cấp). "
            f"Thú lên cấp theo trận thắng khi dắt theo (trùm tính {PR['boss_wins']} trận), cấp N cần {PR['xp_coef']} × N × (N − 1) trận, tối đa cấp {PR['max_level']} "
            f"({n(PR['xp_coef'] * PR['max_level'] * (PR['max_level'] - 1))} trận); chỉ số cộng × (1 + {pct(PR['bonus_per_level'])} × (cấp − 1)). "
            f"Cho ăn ở Người Nuôi Thú: {n(PR['feed_gold'])} × cấp² vàng được {PR['feed_xp']} trận.")
# Hồ Long Vương: bảng cá riêng, Mồi Rồng (công thức của Bà Lang)
_lake = R["fishing"]["pools"]["lake"]; _tot = sum(w for w, _ in _lake)
_bait = next(r for r in D["recipes"] if r["out"] == DRG["bait"])
pet_rule += (f" <b>{E(D['lake']['name'])}</b> (cấp {D['lake']['min_level']}+, không có quái): cá "
             + ", ".join(f"{E(IT[i]['name'])} {pct(w / _tot)}" for w, i in _lake)
             + f"; mỗi {DRG['every'] // 3600} giờ Long Vương nổi một lần vào lúc ngẫu nhiên, ở một ô nước ngẫu nhiên (bọt vàng, trong tầm {DRG['reach']} ô từ bờ), "
             + f"ở lại {DRG['stay'] // 60} phút; chỉ lần thả câu trúng đúng ô đó mới có cơ hội 1/{n(round(1 / DRG['chance']))} Ngài cắn câu (giật trễ thì mất), "
             + f"× (1 + Long Khí / {DRG['long_khi_div']}) (Long Khí +1 mỗi con cá câu ở hồ, tối đa {DRG['long_khi_max']}, về 0 khi câu được Ngài); có {E(IT[DRG['bait']]['name'])} "
             + f"(Bà Lang pha {_bait.get('n', 1)} mồi từ " + " + ".join(f"{k} {E(IT[i]['name'])}" for i, k in _bait["needs"].items())
             + f", nghề Nấu ăn cấp {_bait['level']}) thì tốn 1 mồi mỗi lần thả trúng ô Ngài, cơ hội ×{DRG['bait_mult']}. Có người câu được hoặc hết giờ thì Ngài lặn. "
             + f"Đàn Cá Vàng: khoảng {R['fishing']['school']['every'] // 60} phút một lần một ô lấp lánh {R['fishing']['school']['stay'] // 60} phút, thả trúng ô đó "
             + f"{pct(R['fishing']['school']['gold_chance'])} ra {E(IT[R['fishing']['school']['gold_fish']]['name'])}, mỗi con +{R['fishing']['school']['long_khi']} Long Khí. "
             + f"Việc của Ông Lão mỗi ngày: câu {R['fishing']['elder']['count']} con cá ở hồ → vàng, kinh nghiệm, +{R['fishing']['elder']['long_khi']} Long Khí. Mỗi nhân vật một con; "
             + "người câu được có tên trên Bia Long Vương và danh hiệu Long Vương Chủ.")
pet_tame = (f"Thuần phục: hạ đủ {PR['tame_kills']} con một loài quái thường (vùng chính, bản đồ phụ, vùng chuyển sinh; không thuần được trùm, chúa tể) rồi trả "
            f"({n(PR['tame_price'])} + {PR['tame_price_per_level']} × cấp quái) × (1 + {n(PR['tame_realm_price'])} × k) vàng (k: số vùng chuyển sinh, 0 nếu không phải). "
            f"Thú thuần: công +{pct(PR['tame_bonus'])} + {pct(PR['tame_realm_bonus'])} × k, sức cắn {pct(PR['tame_bite'])} + {pct(PR['tame_realm_bite'])} × k; kỹ năng Cắn Xé rồi Húc Ngã.")
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
luck_real = max(min(LS["luck_max_rate"], st["rate"] + st.get("luck", LS["luck_upgrade"])) for st in D["upgrade"]["steps"] if st["rate"] < 1)
luck_up = ", ".join(f"+{st['level']} {pct(st['luck'])}" for st in D["upgrade"]["steps"] if st.get("luck"))
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

# ---------- Dòng xanh: lấy thêm sau, ép có đổi gì (ví dụ món "relic") ----------
CHR = {r["id"]: r for r in D["chaos"]}
def chaos_need(r):
    items = " + ".join(f"{k} {IT[i]['name']}" for i, k in r["items"].items())
    return f"món +{r['gear']['min_up']} trở lên + {items} + {n(r['gold'])} vàng, tỉ lệ {pct(r['rate'])}" + (f" (+{pct(r['per_up'])} mỗi cấp ép trên +{r['gear']['min_up']}, tối đa {pct(r['max_rate'])})" if r.get("per_up") else "")
LC = ls["luck_chance"]
MONK = {"normal": "quái thường", "elite": "tinh anh", "night": "quái Bóng Đêm", "boss": "trùm"}
lc_txt = ", ".join(f"{MONK.get(k, k)} {pct(v)}" for k, v in LC.items())
step_eff = {st["level"]: st["eff"] for st in D["upgrade"]["steps"]}
lines_rows = "".join(f"<tr><td><b>{a}</b></td><td>{b}</td><td>{c}</td><td>{d}</td><td>{e}</td></tr>" for a, b, c, d, e in [
    ("Kỹ năng (chỉ vũ khí)", f"{pct(ls['skill_chance'])} vũ khí rơi có", "❌ Không thêm được", "1", f"Không — luôn +{pct(ls['skill_dmg'])} sát thương chiêu"),
    ("May mắn", f"theo loại quái: {lc_txt}", f"✅ Pha May mắn (Lão Hỗn Nguyên): {chaos_need(CHR['add_luck'])}" if "add_luck" in CHR else "—", "1",
     f"Không — vũ khí +{pct(ls['luck_crit'])} chí mạng; mọi món cộng tỉ lệ ép ngọc ({luck_up})"),
    ("Dòng cộng thêm (\"Gia tăng lực tấn công / phòng thủ\")", "0–4 dòng khi rơi (xem thẻ bên trên)",
     f"✅ Ngọc Sinh Mệnh (Thợ Rèn): tỉ lệ {pct(life['rate'])} thêm 1 dòng, thất bại mất 1 dòng", str(life["max_lines"]),
     f"Không — mỗi dòng = {pct(life['per_line_pct'])} công / thủ <b>gốc</b> của món (ít nhất +{life['per_line']}), không tính phần ép"),
    ("Excellent (xanh lam: tốc độ đánh, sát thương, chí mạng, hồi máu / MP…)", "theo tỉ lệ Excellent ở mục Tỉ lệ rơi",
     f"✅ Pha Excellent (Lão Hỗn Nguyên): {chaos_need(CHR['add_exc'])}, mỗi lần thêm 1 dòng" if "add_exc" in CHR else "—", "6",
     "Không — giá trị cố định; riêng dòng \"+ cấp × hệ số\" tăng theo <b>cấp nhân vật</b>"),
])
rel = IT.get("relic")
if rel:
    per = max(1, round(rel["atk"] * R["upgrade"]["bonus_pct"]))
    up11 = round(step_eff.get(11, 0) * per)
    line = max(life["per_line"], round(rel["atk"] * life["per_line_pct"]))
    lines_example = (f"Ví dụ <b>{E(rel['name'])} +11</b>, 4 dòng cộng thêm, 6 Excellent: tấn công gốc {rel['atk']}; phần xanh lá "
        f"<b>+{up11 + 4 * line}</b> = ép +11 ({n(step_eff.get(11, 0))} × {per} = +{up11}) + 4 dòng × {line} (= +{4 * line}). "
        f"Ép thêm chỉ đổi phần ép; 4 dòng × {line} và 6 dòng Excellent giữ nguyên. Món đã đủ 4 dòng cộng thêm và 6 Excellent thì không thêm dòng được nữa.")
else:
    lines_example = ""
bm = R["bestiary"]["marks"]
dq = lambda e: R["skill_effects"][e]
rule_items = [
    ("Cấp quái khi tính trúng", "cấp hiện trên quái (vùng chuyển sinh 142–150 là dùng số đó), không phải cấp tính chỉ số."),
    ("Ép cánh", f"sát thương +{pct(WU['dmg']['per_level'][0])} mỗi cấp tới +9, lên +10 thêm {pct(WU['dmg']['jump10'][0])}, lên +11 thêm {pct(WU['dmg']['jump11'][0])}; hấp thụ theo bậc cánh (bảng ở mục Cánh), tổng hấp thụ của cánh tối đa {pct(WU['absorb']['max'])}; phòng thủ cánh theo bảng ép như đồ."),
    ("MP kỹ năng", f"số MP trong bảng là ở cấp 1; tốn = MP × (1 + {n(C['skill_mp_per_level'])} × (cấp − 1)), cộng thẳng, không lũy thừa. Kỹ năng tháp nhân thêm theo lớp: " + ", ".join(f"{CL[c]['name']} ×{n(v)}" for c, v in R['tower_skills'].get('mp_mult', {}).items()) + " (lớp khác ×1)."),
    ("Cột \"Hồi\" (kỹ năng)", "số lượt phải chờ trước khi dùng lại kỹ năng đó (hồi chiêu)."),
    ("Kỹ năng nhiều đòn", "hệ số là tổng, chia đều cho các đòn; chí mạng tính một lần cho cả chiêu, phòng thủ trừ riêng từng đòn."),
    ("Độc, đốt", f"mỗi lượt quái mất một phần sát thương vừa gây (Kiếm Độc Hỏa {pct(dq('venom')['power'])} trong {dq('venom')['turns']} lượt; kỹ năng Tháp ghi ở cột Tác dụng)."),
    ("Phòng thủ của quái", "dùng cùng công thức giảm sát thương: đòn² / (đòn + thủ quái), không dưới " + pct(C["soft_floor"]) + " đòn."),
    ("Đòn đặc biệt của quái", "trùm và một số quái có chiêu riêng, dùng mỗi N lượt (màn trận ghi \"tên chiêu mỗi N lượt\"): mạnh hơn đòn thường, không né được, không chí mạng."),
    ("Sổ tay quái", "hạ đủ " + " / ".join(f"{m['kills']} con (+{pct(m['bonus'])})" for m in bm) + " một loại quái thì đánh loại đó mạnh hơn."),
    ("Đồ rơi theo cấp", "món rơi lấy trong 2 mức cấp cao nhất không quá cấp quái của ô đó, đúng lớp người hạ; \"bộ giáp\" là một món ngẫu nhiên trong mũ, giáp, quần, găng, giày (Đấu Sĩ không có mũ); \"trang sức\" là nhẫn hoặc dây chuyền."),
    ("Đủ bộ, đồ Thần cùng bộ", "đủ bộ tính các món cùng tên bộ, cùng bậc; đồ Thần đếm các món Thần cùng tên bộ. Đấu Sĩ đủ bộ là 4 món (không mũ), cho cả thưởng đủ bộ lẫn mức \"đủ bộ\" của đồ Thần."),
    ("Phí vàng ép", f"max(giá món, {n(UPR['cost_min_price'])}) × {pct(UPR['cost_pct'])} × cấp ép lên."),
    ("May mắn khi ép", f"cộng {luck_up}, trần {pct(LS['luck_max_rate'])}; với bảng ép hiện tại cao nhất là {pct(luck_real)}."),
    ("Thú nuôi", f"ô thú nuôi đeo thú cưng (mua, hoặc thuần hóa loại quái đã hạ {R['pets']['tame_kills']} con); thú cộng % chỉ số và có lúc cắn quái."),
    ("Đài Phúc Lành", f"chạm vào: phúc lành của bản đồ ({R['blessing']['battles']} trận, +{pct(R['blessing']['pct'])} kinh nghiệm / vàng / công / thủ / máu tùy đài) và thành điểm hồi sinh khi gục."),
    ("Bot (người chơi máy)", f"ép đồ như người thật khi dư vàng (giữ lại {R['bots']['forge']['gold_keep_per_level']} × cấp vàng mua bình): +1 → +9 món đang mặc cấp thấp nhất trước, từ +7 chỉ khi dư {R['bots']['forge']['spare']} viên ngọc; thêm dòng Ngọc Sinh Mệnh cho vũ khí, áo giáp; ghép / nâng cánh; +10 / +11 chỉ khoảng 1/{R['bots']['forge']['daring_every']} số bot. Cấp tối đa thì chuyển sinh, cần chúa tể thì đi vùng chuyển sinh săn. Bot không được báo cả server, không vào bảng xếp hạng."),
]
rule_li = "".join(f"<li><b>{k}</b>: {v}</li>" for k, v in rule_items)

# ---------- Vùng chuyển sinh ----------
# mỗi vùng nhiều bản đồ (bản đồ sau mạnh hơn, chúa tể ở bản đồ cuối): mỗi dòng một bản đồ, quái theo chỗ xuất hiện
RM = {m["id"]: m for m in D["realm_monsters"]}
rrows = ""
for mp in sorted(D["maps"], key=lambda m: (m["realm"], len(m["id"]), m["id"])):
    k = mp["realm"]; ms = sorted((RM[i] for i in mp["monsters"] if i in RM), key=lambda m: m["level"])
    reg = [m for m in ms if not m.get("lord")] or ms
    names = ", ".join(E(m["name"]) + (" <b>(chúa tể)</b>" if m.get("lord") else "") for m in ms)
    m0 = reg[0]
    raw = rl["loot_per_realm"] * m0["rich"]
    loot = min(rl["loot_max"], raw)
    rrows += (f"<tr><td class=n>{k}</td><td><b>{E(mp['name'])}</b></td><td class=n>{mp['min_rebirths']}</td><td class=n>{ms[0]['level']}–{ms[-1]['level']}</td>"
              f"<td>{el(m0.get('element'))}</td><td class=n>×{n(round(m0['mult'], 2))} / ×{n(round(m0.get('atk_mult', m0['mult']), 2))}</td><td class=n>+{pct(loot)}{' (trần)' if raw > rl['loot_max'] + 1e-9 else ''}</td>"
              f"<td class=n>{pct(m0['jewel_chance'])}</td><td>{names}</td></tr>")

# ---------- Vật phẩm khác ----------
# nơi mua: cửa hàng (giá gốc; bình thuốc tăng theo cấp nhân vật), vé ở Người Gác Tháp (RULES.<sự kiện>.ticket_price)
TICKET = {v["ticket"]: v["ticket_price"] for v in R.values() if isinstance(v, dict) and v.get("ticket") and v.get("ticket_price")}
# món ăn / đồ uống: nấu / pha ở NPC nào, nguyên liệu, cấp nghề Nấu ăn, kinh nghiệm nghề được
CRAFT_NPC = {"cook": "Bác Đầu Bếp", "herbalist": "Bà Lang"}
RECIPE_OF = {r["out"]: r for r in D.get("recipes", []) if r.get("npc") in CRAFT_NPC}
COOK_LV = D["rules"]["crafting"]["cook_levels"]
def craft_at(r):
    needs = " + ".join(f"{k} {E(IT[i]['name'])}" for i, k in r["needs"].items())
    xp = r.get("xp", 1)
    return (f"{CRAFT_NPC[r['npc']]}: {needs}<br><small>nghề Nấu ăn cấp {r.get('level') or 1} · "
            + (f"+{xp} kinh nghiệm nghề" if xp else "không cộng kinh nghiệm nghề") + "</small>")
def buy_at(i, v):
    if i in RECIPE_OF:
        return craft_at(RECIPE_OF[i])
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
         grp(f"Món ăn (Bác Đầu Bếp; nghề Nấu ăn cấp 1–{len(COOK_LV)} ở {' / '.join(map(str, COOK_LV))} kinh nghiệm)", ["cha_ca", "banh_mi_ca", "banh_xeo_luon", "mam_co"]) +
         grp("Đồ uống (Bà Lang, cộng dồn với món ăn)", ["bia_thao_duoc", "ruou_thuoc", "ruou_linh_chi", "ruou_long_huyet"]) +
         grp("Mồi câu (Bà Lang)", ["dragon_bait"]) +
         grp("Ngọc", ["jewel_bless", "jewel_soul", "jewel_chaos", "jewel_life"]) +
         grp("Vé và nguyên liệu sự kiện", ["ds_ticket", "bc_ticket", "cc_ticket", "devil_eye", "devil_key", "archangel_scroll", "blood_bone",
                                           "kundun_mark", "lost_map", "condor_feather"]) +
         grp("Nguyên liệu thu thập", ["herb", "herb_rare", "ore", "ore_rare", "fish_small", "fish_carp", "fish_eel", "fish_gold", "old_boot", "dragon_scale"]) +
         grp("Quà lễ hội", ["moon_cake", "pumpkin_candy", "gift_box", "lucky_apple"]))

# rèn đồ ở Thợ Rèn (Crafting.smith/2): giá, ngưỡng nghề, tỉ lệ số dòng theo cấp nghề
CR = D["rules"]["crafting"]
SMITH_SLOT = {"weapon": "vũ khí", "armor": "giáp (một món của bộ)", "shield": "khiên"}
smith_cost = "; ".join(f"{SMITH_SLOT.get(k, k)} " + " + ".join(f"{q} {E(IT[i]['name'])}" for i, q in c.items())
                       for k, c in CR["smith_costs"].items())
smith_note = (f"<b>Rèn đồ ở Thợ Rèn</b>: ra một món đúng cấp, đúng lớp người rèn, chọn được ô, luôn có ít nhất 1 dòng cộng thêm. "
              f"Giá: {smith_cost}, + cấp nhân vật × {CR['smith_gold_per_level']} vàng. "
              f"Nghề Rèn cấp 1–{len(CR['levels'])} ở {' / '.join(map(str, CR['levels']))} lần rèn (mỗi lần +1). "
              f"Số dòng: 3 dòng {CR['smith_epic_per_level']}% × cấp nghề (cấp {len(CR['levels'])}: {CR['smith_epic_per_level'] * len(CR['levels'])}%), "
              f"2 dòng {CR['smith_rare']}%, còn lại 1 dòng.")
page = open(os.path.join(os.path.dirname(__file__), "tpl.html"), encoding="utf-8").read()
for k, v in dict(OVERVIEW=overview, TABS=tabs, PANES=panes, TIERS=trows, JEW=jrows, WINGS=wrows, WINGUP=wuprows, UPG=erows, EXC_W=exl("weapon"),
                 EXC_A=exl("armor"), ANC=anc_li, OPT=opt_li, LOOT=lrows, SLOTS=", ".join(slot_txt), STABS=stabs, SPANES=spanes,
                 CYCLE=cycle, BYLV=bylv, REALMS=rrows, OTHER=other, STATROWS=stat_rows, MODEROWS=mode_rows, MONSTER=monster_line, RULELI=rule_li, GAPS=gap_note, EVROWS=ev_rows, FEST=fest, MAPROWS=map_rows, BOSSROWS=boss_rows, BOSSNOTE=boss_note, TOWERROWS=tower_rows, PKLI=pk_li, PETROWS=pet_rows, PETRULE=pet_rule, PETTAME=pet_tame, PETSK1=str(PR['skill_level']), PETSK2=str(PR['skill2_level']), TWHARD=str(TW['harder_from']), TWPER=pct(TW['harder_per_floor']), TWBOSS=str(TW['boss_every']), TWELITE=n(TW['elite_mult']), TWOFF=str(TW['level_offset']), TRAVEL=f"{R['travel']['base']} + {R['travel']['per_level']} × cấp quái thấp nhất", CLASSROWS=class_rows, EVSCALE=f"<b>Quái sự kiện mạnh theo số lần chuyển sinh k của người đánh</b> (Quảng Trường Quỷ, Lâu Đài Máu, Kalima, Hỗn Chiến Thành, Vương Miện Công Thành Chiến, quái vàng): máu và thủ × (1 + {n(R['event_scale']['hp_per_rebirth'])} × k), công × (1 + {n(R['event_scale']['atk_per_rebirth'])} × k), kinh nghiệm và vàng × (1 + {n(R['event_scale']['reward_per_rebirth'])} × k); k tối đa {R['character']['max_rebirths']}. Trùm thế giới và tháp không áp.", SMITH=smith_note, CHAOSROWS=chaos_rows, LINESROWS=lines_rows, LINESEX=lines_example, JEWELSRC=jewel_src, POTLV=pct(R['shop']['potion_price_per_level']), RLOOT=pct(rl['loot_per_realm']), RLOOTMAX=pct(rl['loot_max']), LUCKREAL=pct(luck_real), COSTMIN=n(UPR['cost_min_price']), COSTPCT=pct(UPR['cost_pct']),
                 SB=f"+{pct(sb['def_pct'])} thủ, +{pct(sb['atk_pct'])} công, +{sb['hp_per_tier']} máu × bậc bộ",
                 UPPCT=pct(R['upgrade']['bonus_pct']), ANNOUNCE=str(up['announce_from']), DOUBLE=str(up['double_from']),
                 LUCKUP=luck_up, LUCKMAX=pct(ls['luck_max_rate']), LUCKCRIT=pct(ls['luck_crit']), SKILLDMG=pct(ls['skill_dmg']),
                 LIFE=f"{pct(life['per_line_pct'])} công / thủ gốc của món (ít nhất +{life['per_line']}) mỗi dòng, tối đa {life['max_lines']} dòng, {pct(life['rate'])}",
                 EXCLINES=", ".join(f"{a} dòng {pct(b/sum(w for _, w in ex['lines']))}" for a, b in ex["lines"]),
                 EXCPRICE=n(ex['price_mult']), DMGRED=pct(ex['max_dmg_red']), REFL=pct(ex['max_reflect']),
                 ANCDEF=pct(anc['piece_def_pct']), ANCPRICE=n(anc['price_mult']), PERLINE=f"{pct(life['per_line_pct'])} công / thủ gốc của món (ít nhất +{life['per_line']})",
                 STRONG=pct(EL['strong']), WEAK=pct(EL['weak']), LOADOUT=str(R['tower_skills']['loadout']), MASTERY=mastery_note(),
                 RMIN=str(rl['min_level']), REBIRTH=f"Chuyển sinh lần n: +{R['character']['rebirth_points']} × n điểm tiềm năng, kinh nghiệm lên cấp × (1 + {pct(R['character']['rebirth_xp_pct'])} × n); từ lần {R['character']['rebirth_lord_from'] + 1}, muốn chuyển sinh lần k + 1 phải từng hạ chúa tể vùng k.", RSTAT=str(rl['stat_level']), RMULT=n(rl['mult_per_realm']), RXP=n(rl['xp_mult_per_realm']), RBOSS=n(rl['boss_mult']), RMAPS=str(rl['maps_per_realm']), RSTEP=n(rl['depth_step']),
                 SELL=pct(R['shop']['sell_ratio'])).items():
    page = page.replace("{{" + k + "}}", v)
assert "{{" not in page, page[page.index("{{"):page.index("{{") + 40]
open(OUT, "w", encoding="utf-8").write(page)
json.dump(sorted(USED), open(OUT + ".files.json", "w"))
print(len(page), "bytes,", len(USED), "hình")

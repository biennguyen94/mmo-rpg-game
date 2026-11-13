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
C, MON, PV = R["combat"], R["monster"], R["pvp"]
CLN = {"dk": "Kiếm Sĩ", "dw": "Phù Thủy", "elf": "Tiên Nữ", "mg": "Đấu Sĩ"}
pv_cls = "theo bảng hệ số lớp theo số lần chuyển sinh của người bị đánh (dưới bảng này)"
TK = PV.get("class_taken_by_rebirth", {})
def taken_table(TK):
    return "".join(f"<tr><td><b>{k}</b></td>" + "".join(f"<td>×{n(TK[k][c])}</td>" for c in CLN) + "</tr>" for k in sorted(TK, key=int))
taken_rows = taken_table(TK)
taken_arena = taken_table(PV.get("class_taken_arena_by_rebirth", TK))
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
    f"<tr><td><b>Sát thương</b></td><td>đầy đủ</td><td>mọi sát thương lên người (đòn thường, kỹ năng, độc) ×{n(PV['dmg_mult'])}, nhân thêm theo lớp người bị đánh: {pv_cls}</td></tr>",
    "<tr><td><b>Mình trúng</b></td><td>đòn thường theo tỉ lệ trúng quái; quái không né; kỹ năng luôn trúng</td><td>đòn thường theo né đối thủ; kỹ năng luôn trúng</td></tr>",
    "<tr><td><b>Mình bị đánh</b></td><td>né được đòn thường; đòn đặc biệt của quái không né được</td><td>né được đòn thường; kỹ năng của đối thủ không né được</td></tr>",
    f"<tr><td><b>Chí mạng</b></td><td>của mình; quái theo số ở trên</td><td>tỉ lệ ×{n(PV['crit_rate_mult'])}, phần cộng thêm của hệ số ×{n(PV['crit_bonus_mult'])} (thu nhỏ theo tỉ lệ, không chặn trần)</td></tr>",
    f"<tr><td><b>Choáng</b></td><td>quái mất lượt</td><td>tỉ lệ choáng ×{n(PV['stun_mult'])} (mọi kỹ năng, cả Thủy Long Ba); bị choáng mất một lượt; vừa thoát choáng thì kháng {PV['stun_immune']} lượt</td></tr>",
    "<tr><td><b>Hiệu ứng lên nhau</b></td><td>choáng, suy yếu, độc lên quái; buff lên mình</td><td>choáng, suy yếu, độc / bỏng mình gây chuyển sang người bị đánh (độc trừ máu đầu lượt của họ); thủ thế, khiên, Bất Tử, Ảnh Bộ, giảm sát thương của thú (nhóm Hộ vệ, Long Vương) của người bị đánh vẫn đỡ đòn; Long Uy (Long Vương) kháng một nửa choáng / độc / suy yếu; Bất Tử mỗi trận chỉ cứu một lần, dùng lại Bất Tử không cứu thêm</td></tr>",
    f"<tr><td><b>Bình máu</b></td><td>uống được mọi lượt</td><td>hồi ×{n(PV['potion_mult'])} nhưng mỗi bình tối đa {pct(PV['potion_cap_pct'])} máu tối đa (bình to cỡ nào cũng vậy); mỗi {PV['potion_cd']} lượt của mình uống được một lần, tối đa {PV['potion_max']} bình mỗi trận (mất lượt như đánh quái)</td></tr>",
    f"<tr><td><b>Bình mana</b></td><td>uống được mọi lượt</td><td>hồi ×{n(PV['mana_mult'])}, mỗi bình tối đa {pct(PV['mana_cap_pct'])} MP tối đa; mỗi {PV['mana_cd']} lượt một bình, tối đa {PV['mana_max']} bình mỗi trận (đếm riêng với bình máu)</td></tr>",
    f"<tr><td><b>Hồi máu kỹ năng</b></td><td>đầy đủ</td><td>×{n(PV['heal_mult'])} (Hồi Sinh Lực, Tăng Sức Mạnh, Phúc Lành…); thú không hồi máu (chỉ cộng chỉ số); hút máu và khiên không đổi</td></tr>",
    "<tr><td><b>Giảm sát thương</b></td><td>thủ thế, khiên, thú che chắn, hấp thụ cánh, Excellent</td><td>cả hai bên: hấp thụ cánh, Excellent, bỏ qua phòng thủ; thêm thủ thế / khiên / thú của người bị đánh</td></tr>",
    "<tr><td><b>Phản sát thương (Excellent)</b></td><td>quái mất phần phản lại nhưng không chết vì phản đòn (còn ít nhất 1 máu)</td><td>Đồ sát: người đánh mất phần phản lại, còn ít nhất 1 máu; Đấu trường: phản đòn hạ được đối thủ, cả hai chiều (Bất Tử vẫn cứu)</td></tr>",
    f"<tr><td><b>Kỹ năng</b></td><td>bộ {R['tower_skills']['loadout']} kỹ năng mang vào trận</td><td>như đánh quái; đối thủ Đấu trường (máy) dùng kỹ năng mạnh nhất, thú, buff, hồi máu, uống bình máu dưới một nửa máu, khiên đỡ đòn, chịu độc và suy yếu như người</td></tr>",
    f"<tr><td><b>Thắng thua</b></td><td>hết máu</td><td>hết máu; Đồ sát: luân phiên lượt, người tấn công đi trước, đòn mở màn (lượt đầu) chỉ gây ×{n(R['slay']['first_strike_mult'])} sát thương; Đấu trường: đòn mở màn của người thách đấu chỉ gây ×{n(R['arena'].get('first_strike_mult', 1))} sát thương, cả hai cùng gục thì bên bị đánh lố ít hơn thắng</td></tr>",
])
mh, ma, md = MON["hp"], MON["atk"], MON["def"]
monster_line = (f"Quái cấp L: máu {n(mh['base'])} + {n(mh['level'])}L + {n(mh['level_sq'])}L², công {n(ma['base'])} + {n(ma['level'])}L, "
                f"thủ {n(md['base'])} + {n(md['level'])}L. Quái không né (mình trúng theo tỉ lệ trúng). "
                f"Trùm: máu ×{n(MON['boss']['hp'])}, công ×{n(MON['boss']['atk'])}, thủ ×{n(MON['boss']['def'])}, kinh nghiệm ×{n(MON['boss']['xp'])}, vàng ×{n(MON['boss']['gold'])}, "
                f"thêm chiêu đặc biệt mỗi vài lượt. Quái Bóng Đêm ({pct(R['world']['night_rare_chance'])} quái mới sinh ban đêm): máu / công / thủ ×{n(R['world']['night_rare_mult'])}.")

# ---------- Sự kiện (RULES: devil_square, blood_castle, chaos_castle, kalima, castle_siege, raids, invasion; world_boss) ----------
LIB = D["library"]
MON = {m["id"]: m for m in LIB["monsters"]}
MAPN = {m["id"]: m["name"] for m in LIB["maps"]}
# bản đồ riêng đấu trực tiếp không có trong Thư viện: đọc tên từ file bản đồ
DUELN = json.load(open(os.path.join(os.path.dirname(__file__), f"../../priv/maps/{R['arena']['duel_map']['map']}.json"), encoding="utf-8"))["name"]
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
def ev_row(name, when, who, entry, how, reward, pk=None, cs=None, tip=None):
    rows = [("Khi nào", when), ("Ai vào", who), ("Vào bằng", entry), ("Diễn biến", how), ("Thưởng", reward)]
    if pk: rows.append(("Đánh người", pk))
    if cs: rows.append(("Theo chuyển sinh", cs))
    if tip: rows.append(("Mẹo", tip))
    return f'<div class="card ev"><h3>{name}</h3><dl>' + "".join(f"<dt>{k}</dt><dd>{v}</dd>" for k, v in rows) + "</dl></div>"
waves = " + ".join(str(w["count"]) + (" (trùm)" if w["boss"] else "") for w in ds["waves"])
top = "; ".join(f"hạng {i + 1}: {n(t['gold'])} vàng + {items_txt(t['items'])}" for i, t in enumerate(ds["top"]))
ka_mark = E(IT[ka["mark"]]["name"]) if ka["mark"] in IT else ka["mark"]
# quái sự kiện theo chuyển sinh (scripts/kho_do/event_monsters.exs): chỉ số + so với nhân vật cùng mốc
def evmon_rows():
    out = []
    for m in D.get("event_monsters", []):
        rs = m["rows"]
        for i, r in enumerate(rs):
            head = f'<td rowspan="{len(rs)}"><b>{E(m["name"])}</b><br><span class="muted">cấp {m["level"]}</span></td>' if i == 0 else ""
            vs = "".join(f'<td>{r["vs"][c]["hits"]} đòn · {r["vs"][c]["taken"]}%</td>' for c in ("dk", "dw", "elf", "mg"))
            out.append(f'<tr>{head}<td>{r["k"]}</td><td class=n>{n(r["hp"])}</td><td class=n>{n(r["atk"])}</td><td class=n>{n(r["def"])}</td>{vs}</tr>')
    return "".join(out)
evmon = evmon_rows()

_es, _st, _wbr, _bm = R["event_scale"], R["starter_events"], R["world_boss"], R["blood_moon"]
_bands = ", ".join(f"{a}–{b}" if b < R["character"]["max_rebirths"] else f"{a}+" for a, b in R["event_rooms"]["bands"])
_room_cs = (f"phòng theo số lần chuyển sinh ({_bands}); quái của phòng mạnh theo mốc cao nhất của phòng k: máu, thủ × (1 + {n(_es['hp_per_rebirth'])} × k), "
            f"công × (1 + {n(_es['atk_per_rebirth'])} × k), vàng, kinh nghiệm × (1 + {n(_es['reward_per_rebirth'])} × k), k tối đa {R['character']['max_rebirths']} (xem bảng dưới)")
_no_pk = "không (bản đồ riêng theo phòng / tổ đội)"
_jn = ", ".join(E(IT[j]["name"]) for j in _bm["jewels"])
_lake, _school, _bird, _flock, _met = R["fishing"]["dragon"], R["fishing"]["school"], R["sky"]["bird"], R["sky"]["flock"], R["sky"]["meteor"]
_starter = (f"thêm {_st['realm_pick']} bản đồ đầu vùng chuyển sinh ngẫu nhiên mỗi đợt, quái mạnh như vùng đó; ở bản đồ đầu vùng thường, "
            f"trùm chỉ rơi ngọc / đồ thêm cho người <b>dưới chuyển sinh {_st['jewel_max_rebirths']}</b> (người chuyển sinh cao hạ được vẫn nhận vàng, kinh nghiệm)")
ev_rows = "".join([
    ev_row("😈 Quảng Trường Quỷ", f"{clock(ds['every_hours'], ds['offset_hours'] * 60)}; vào trong {ds['entry_minutes']} phút, đánh {ds['run_minutes']} phút",
           f"cấp {ds['min_level']}+; {tiers_txt(ds['tiers'])}", ticket_txt(ds),
           f"{len(ds['waves'])} đợt quái ({waves}), quái mỗi đợt mạnh dần; điểm: quái {ds['score']['monster']}, trùm {ds['score']['boss']}; cùng phòng chung quái, chung máu quái",
           f"vàng, kinh nghiệm theo điểm; mỗi {ds['reward']['jewel_every']} điểm 1 ngọc; qua hết đợt được 1 món đồ ({pct(ds['reward']['clear_exc_chance'])} Excellent, {pct(ds['reward']['clear_anc_chance'])} Thần). Top ngày (thư lúc 0h): {top}",
           pk=_no_pk, cs=_room_cs, tip="Đi đông người cùng phòng: quái chung máu, ai gây sát thương cũng được phần; giữ kỹ năng mạnh cho trùm đợt cuối."),
    ev_row("🏰 Lâu Đài Máu", f"{clock(bc['every_hours'], bc['offset_minutes'])}; vào trong {bc['entry_minutes']} phút, đánh {bc['run_minutes']} phút",
           f"cấp {bc['min_level']}+; {tiers_txt(bc['tiers'])}", ticket_txt(bc),
           f"hạ {bc['guards']} quái canh → phá {E(bc['gate']['name'])} (không đánh trả, máu ×{bc['gate']['hp_mult']}) → hạ {E(bc['boss']['name'])}",
           f"thắng: vàng, kinh nghiệm, {items_txt(bc['reward']['success']['items'])}, {bc['reward']['success']['jewels']} ngọc; người gây nhiều sát thương nhất lên trùm nhận Lông Vũ; không xong: thưởng theo số quái canh đã hạ",
           pk=_no_pk, cs=_room_cs),
    ev_row("⚔ Hỗn Chiến Thành", f"{clock(cc['every_hours'], cc['offset_minutes'])}; vào trong {cc['entry_minutes']} phút, đánh {cc['run_minutes']} phút",
           f"cấp {cc['min_level']}+; quái quanh cấp trung bình người vào (±{cc['level_spread']})", ticket_txt(cc),
           f"<b>sinh tồn</b>: {cc['total']} đối thủ (quái + người, ít nhất {cc['min_monsters']} quái); gục là <b>bị loại</b>; hết giờ vào thì đóng cửa",
           f"người cuối cùng: {n(cc['reward']['winner']['gold'])} vàng + {items_txt(cc['reward']['winner']['items'])}; trụ tới hết giờ: {n(cc['reward']['survivor']['gold'])} vàng + {items_txt(cc['reward']['survivor']['items'])}; mỗi người hạ được +{n(cc['reward']['per_player_kill'])} vàng",
           pk="có, ai cũng đánh ai khi đã vào giờ hỗn chiến; không mất vàng, không tên đỏ", cs=_room_cs,
           tip="Khác Pháp Trường: ở đây gục là hết lượt, nên trốn và chọn trận quan trọng hơn hạ thật nhiều."),
    ev_row("🩸 Pháp Trường Huyết Nguyệt", f"quản trị mở ({_bm['minutes']} phút mặc định, 1–{_bm['minutes_max']}) hoặc lịch hằng ngày (báo trước {_bm['warn_min']} phút)",
           f"cấp {D['bm_map']['min_level']}+, cổng phía nam Làng", "không cần",
           f"<b>săn người, tranh điểm</b>: bản đồ 60×40 không quái; gục về Làng, {_bm['relock_s']} giây sau vào lại. "
           f"Điểm mỗi mạng {n(_bm['points']['base'])} + {n(_bm['points']['step'])} × (chuyển sinh người gục − mình), từ {n(_bm['points']['min'])} tới {n(_bm['points']['max'])}. "
           f"<b>Huyết Sát</b>: hạ {_bm['streak']['min']} người liên tiếp không gục thì cả bản đồ thấy cột sáng đỏ; hạ được Huyết Sát +{_bm['streak']['bounty_points']} điểm, cơ hội ngọc ×{n(_bm['streak']['bounty_drop_mult'])}. "
           f"<b>Bàn thờ Huyết Ngọc</b> giữa sân: mỗi {_bm['altar']['every_s'] // 60} phút sáng {_bm['altar']['window_s']} giây, đứng một mình đủ {_bm['altar']['hold_s']} giây (không đang đánh) nhận 1 ngọc; người thứ hai lên thì tạm dừng",
           f"hạ người: {pct(_bm['drop_pct'])} rơi 1 viên ({_jn}), × (1 + {n(_bm['rebirth_step'])} × chênh chuyển sinh) tới ×{n(_bm['rebirth_max'])}, hạ lại cùng người ×{n(_bm['repeat_decay'])}; hạ bot chỉ tính điểm. "
           "Trăng lặn: top 3 người thật nhiều điểm nhất (≥ " + str(_bm['min_kills']) + " mạng) nhận ngọc qua thư, mặc định " +
           "; ".join(f"hạng {i + 1}: " + ", ".join(f"{v} {E(IT[k]['name'])}" for k, v in rw.items()) for i, rw in enumerate(_bm['top_rewards'])) + " (quản trị chỉnh được)",
           pk="có, cả cùng tổ đội, chỉ lúc trăng mọc; không mất vàng, không tên đỏ (trận bắt đầu lúc trăng mọc vẫn tính vậy dù trăng lặn giữa trận)",
           cs="điểm và cơ hội ngọc cao hơn khi hạ người chuyển sinh nhiều hơn mình; hạ người yếu hơn nhiều gần như không được gì",
           tip="Săn Huyết Sát để lấy điểm thưởng; canh Bàn thờ sáng khi xung quanh vắng; quản trị có thể gọi bot vào cho đông."),
    ev_row("🌀 Kalima", "lúc nào cũng vào được", f"cấp {ka['min_level']}+; {tiers_txt(ka['tiers'])}", ticket_txt(ka) + f" (ghép từ 5 {ka_mark}, rơi {pct(ka['mark_drop']['chance'])} từ quái cấp {ka['mark_drop']['min_level']}+)",
           f"bản đồ riêng theo tổ đội {ka['run_minutes']} phút: hạ {ka['guards']} quái → {E(ka['boss']['name'])} xuất hiện",
           f"hạ {E(ka['boss']['name'])}: vàng, kinh nghiệm, {ka['reward']['success']['jewels']} ngọc, 1 món đồ ({pct(ka['reward']['success']['exc_chance'])} Excellent, {pct(ka['reward']['success']['anc_chance'])} Thần); không xong: theo số quái đã hạ",
           pk=_no_pk, cs="quái mạnh theo người chuyển sinh nhiều nhất trong tổ đội (công thức như phòng sự kiện)", tip="Kundun đánh rất đau ở chuyển sinh cao: đi tổ đội, mang đủ bình máu."),
    ev_row("👑 Công Thành Chiến", f"{WD[cs['weekday']]} {cs['hour']}h{cs['minute']:02d}, {cs['run_minutes']} phút",
           f"thành viên (cấp {cs['min_level']}+) của bang đã đăng ký và bang giữ thành", f"bang chủ / phó đăng ký ở Người Gác Tháp ({n(cs['register_gold'])} vàng)",
           f"giữ {E(cs['crown']['name'])} giữa thành (hạ được thì giữ, hiện lại sau {cs['crown']['respawn_s']} giây)",
           f"bang giữ Vương Miện lúc hết giờ là Chủ Thành tới trận sau; mỗi thành viên {n(cs['reward']['gold'])} vàng + {items_txt(cs['reward']['items'])}",
           pk="có, chỉ người bang khác, trong lúc đánh; không mất vàng, không tên đỏ", cs=f"Vương Miện cố định như chuyển sinh {_es['crown_rebirths']}: người chuyển sinh thấp bị đánh rất đau, cần cả bang"),
] + [ev_row(f"{v['icon']} {E(v['name'])}", f"{clock(v['every_hours'], v['offset_minutes'])}, {v['minutes']} phút", "mọi người",
            "không cần", f"{v['leader']['count']} {E(v['leader']['name'])} (cấp + {v['leader']['level_bonus']}, sức ×{n(v['leader']['mult'])})" +
            (f" và {v['minion']['count']} {E(v['minion']['name'])}" if v.get("minion") else "") + f" ở {v['pick']} bản đồ ngẫu nhiên trong {len(v['maps'])} vùng chính + {_st['realm_pick']} bản đồ vùng chuyển sinh; hạ hết thì xong sớm",
            f"thưởng ×{v['reward_mult']}; con đầu đàn chắc chắn rơi ngọc, thêm " + ", ".join(f"{E(IT[k]['name'])} {pct(c)}" for k, c in v["drops"].items()),
            pk="có (luật đồ sát thường: mất vàng, tên đỏ)", cs=_starter)
   for v in rd.values() if isinstance(v, dict) and v.get("leader")] + [
    ev_row("✨ Golden Invasion (quái vàng)", f"{clock(inv['every_hours'])}, {inv['minutes']} phút", "mọi người", "không cần",
           f"{sum(inv['maps'].values())} quái vàng ở {len(inv['maps'])} vùng chính (sức ×{n(inv['strength_mult'])}); hạ hết một bản đồ thì trùm vàng xuất hiện; "
           f"+ {_st['invasion_count']} quái vàng ở {_st['realm_pick']} bản đồ vùng chuyển sinh (không trùm vàng)",
           f"thưởng ×{inv['reward_mult']}, quái vàng {pct(inv['jewel_chance'])} rơi ngọc, trùm vàng chắc chắn",
           pk="có (luật đồ sát thường); người đang đánh quái vàng vẫn bị đồ sát", cs=_starter),
    ev_row("🐉 Trùm thế giới Cổ Long", f"lần đầu {WB.get('first_after_minutes')} phút sau khi máy chủ chạy, rồi cứ {WB.get('every_minutes')} phút sau khi con trước gục / bay đi; ở {WB.get('duration_minutes')} phút",
           "mọi người, ở Tế Đàn", "không cần",
           f"cả máy chủ đánh chung một thanh máu: {n(WB.get('hp'))} + {n(_wbr['hp_per_fighter'])} cho mỗi người mới vào đánh trong {_wbr['grow_minutes']} phút đầu (tối đa {n(_wbr['hp_cap'])})",
           f"chia vàng, kinh nghiệm theo phần sát thương; gây ≥ {pct(_wbr['join_min_share'])} máu: + " + ", ".join(f"{v} {E(IT[k]['name'])}" for k, v in _wbr['join_items'].items()) +
           "; 3 người gây nhiều nhất thêm Vảy Cổ Long + 1 ngọc; đòn cuối thêm vàng; hết giờ chưa hạ thì không ai được",
           pk="có (luật thường); bị đồ sát giữa trận với trùm thì trận với trùm bị cắt, sát thương đã gây vẫn tính", cs="không tăng theo chuyển sinh; máu tăng theo số người đánh để người chuyển sinh cao không hạ quá nhanh"),
    ev_row("🗼 Tháp Vô Tận", "lúc nào cũng vào (Người Gác Tháp)", "mọi người", "không cần",
           f"leo từng tầng; từ tầng {R['tower']['harder_from']} mỗi tầng mạnh thêm {pct(R['tower']['harder_per_floor'])}; trùm mỗi {R['tower']['boss_every']} tầng; tầng 61–160 dùng quái vùng chuyển sinh, sau đó quay vòng",
           "vàng, kinh nghiệm, đồ theo tầng (bảng ở mục Tháp Vô Tận); kỷ lục tầng 10, 20 … 100 mở kỹ năng Tháp",
           pk=_no_pk, cs="sức quái theo tầng, không theo chuyển sinh"),
    ev_row("🌙 Động Bí Ẩn", f"ban đêm (20h–5h), {pct(R['secret']['open_chance'])} số đêm cửa mở (khe đá sau Đền Cổ); trùm {R['secret']['boss_from_h']}h–{R['secret']['boss_to_h']}h, báo trước {R['secret']['warn_min']} phút",
           "cấp 38+", "khe đá sau Đền Cổ (chỉ đêm mở)",
           f"động tối, chỉ sáng quanh mình; {pct(R['secret']['elite_chance'])} quái là Tinh Anh (sức ×{n(R['secret']['elite_mult'])}, thưởng ×{R['secret']['elite_reward']}, ngọc ×{n(R['secret']['elite_jewel_mult'])}); trùm đêm Thạch Long Ẩn",
           f"trùm: " + ", ".join(f"{v} {E(IT[k]['name'])}" for k, v in R['secret']['boss_items'].items() if k in IT) + "; Bia Động Bí Ẩn ghi người tìm ra động đầu tiên mỗi đêm và người hạ trùm",
           pk="có (luật thường); động tối, khó thấy người tới", cs="trùm đêm mạnh theo chuyển sinh người đánh (như trùm vùng)"),
    ev_row("🎣 Biển Long Vương, Đàn Cá Vàng", f"Long Vương nổi mỗi {_lake['every'] // 60} phút ở một ô nước ngẫu nhiên ({_lake['stay'] // 60} phút); Đàn Cá Vàng mỗi {_school['every'] // 60} phút ({_school['stay'] // 60} phút)",
           f"cấp {D['lake']['min_level']}+", "cổng từ Rừng / Đồi Sáo Diều",
           f"thả câu trúng đúng ô Long Vương: cơ hội 1/{int(1 / _lake['chance'])} mỗi lần, nhân theo Long Khí (mỗi cá +1, tối đa {_lake['long_khi_max']}), Mồi Rồng ×{_lake['bait_mult']}; Đàn Cá Vàng: {pct(_school['gold_chance'])} ra Cá Chép Vàng, +{_school['long_khi']} Long Khí",
           "thần thú Long Vương (đã có thì Cá Chép Vàng); cá, Long Khí",
           pk=f"chỉ từ lúc báo {R['slay']['event_pk']['warn_min']} phút trước khi Ngài nổi tới khi Ngài nổi; ngoài khung đó là vùng an toàn"),
    ev_row("🪁 Đồi Sáo Diều (Chim Lạc, Đàn Hạc, sao băng)", f"Chim Lạc mỗi {_bird['every'] // 60} phút ({_bird['stay'] // 60} phút); Đàn Hạc mỗi {_flock['every'] // 60} phút ({_flock['stay'] // 60} phút); sao băng ban đêm mỗi {_met['every'] // 60} phút ({_met['count']} viên)",
           "cấp 30+", "cổng mép phải Biển Long Vương",
           f"thả diều trúng ô Chim Lạc: cơ hội 1/{int(1 / _bird['chance'])}, nhân theo Phong Khí (tối đa {_bird['phong_khi_max']}), Sáo Đồng ×{_bird['bait_mult']}; Đàn Hạc: +{_flock['phong_khi']} Phong Khí, quà gió quý hơn; nhặt Mảnh Sao rơi trên đồi",
           "thần thú Chim Lạc; Lông Hạc, Mảnh Mây, ngọc, Mảnh Sao (ghép Sáo Đồng)",
           pk=f"chỉ từ lúc báo {R['slay']['event_pk']['warn_min']} phút trước khi Chim Lạc tới tới khi chim xuất hiện"),
])
# đổi vật phẩm lễ hội ở Người Tổ Chức Hội (RULES.events, DECISIONS "Lễ hội: nâng phần thưởng")
EVR = R["events"]
_gw = sum(w for _, w in EVR["gear_weights"])
fest_shop = "".join(f"<tr><td>{a}</td><td class=n>{c}</td></tr>" for a, c in [
    (f"Vàng: ({EVR['gold_base']} + {EVR['gold_per_level']} × cấp) × (1 + {n(EVR.get('gold_per_rebirth', 0))} × số lần chuyển sinh)", EVR["shop"]["gold"]),
    (f"{EVR['potions']} {E(IT['potion_l']['name'])}", EVR["shop"]["potions"]),
    ("Túi Quà Lễ Hội: một món hợp cấp, dòng cộng thêm " + ", ".join(f"+{4 * k} ({k} dòng) {pct(w / _gw)}" for k, w in EVR["gear_weights"]) +
     (f"; {pct(EVR['exc_chance'])} thêm một dòng Excellent" if EVR.get("exc_chance") else ""), EVR["shop"]["gear"]),
] + [(E(IT[j["id"]]["name"]), j["cost"]) for j in EVR.get("jewels", [])])
fest = "".join(f"<tr><td>{e['icon']} <b>{E(e['name'])}</b></td><td>{e['from']} → {e['to']}</td><td>{E(e['desc'])}</td><td>{E(IT[e['token']]['name']) if e.get('token') in IT else '—'}</td></tr>"
               for e in D["festivals"])


# ---------- Thang vùng co giãn theo server (lib/hac_long/realm_ladder.ex, RULES.realms.ladder) ----------
LD = rl["ladder"]
def _pct_at(sorted_s, p):
    i = max(0, min(len(sorted_s) - 1, -(-int(p * len(sorted_s) * 1000) // 1000) - 1)) if False else max(0, min(len(sorted_s) - 1, int(__import__("math").ceil(p * len(sorted_s))) - 1))
    return sorted_s[i]
def ladder_compute(sample, prev):
    if len(sample) < LD["min_sample"]:
        return prev, []
    s_ = sorted(sample); tg = [_pct_at(s_, p) for p in LD["percentiles"]]; ks = []; before = 0
    for i in range(1, len(LD["percentiles"]) + 1):
        old = prev[i - 1]
        want = max(i, tg[i - 1], before + 1)
        k = max(i, before + 1, max(old - LD["max_step"], min(old + LD["max_step"], want)))
        ks.append(k); before = k
    return ks, tg
def ladder_curve(k, per, aft):
    return 1 + per * min(k, 10) + aft * max(0, k - 10)
# ví dụ: 200 người, chuyển sinh rải 8–30 (server lâu năm), tính lại mỗi ngày tới khi ổn định
_ex = [8 + (i * 7) % 23 for i in range(200)]
_ks = list(range(1, 11)); _days = 0
while True:
    _new, _tg = ladder_compute(_ex, _ks); _days += 1
    if _new == _ks or _days > 30: break
    _ks = _new
_new_day1, _ = ladder_compute(_ex, list(range(1, 11)))
ladder_rows = "".join(f"<tr><td>Vùng {i + 1}</td><td class=n>{pct(LD['percentiles'][i])}</td><td class=n>{i + 1}</td><td class=n>{_new_day1[i]}</td><td class=n><b>{_ks[i]}</b></td>"
                      f"<td class=n>×{ladder_curve(_ks[i], rl['mult_per_realm'], LD['hp_after']):.2f} / ×{ladder_curve(_ks[i], rl['atk_mult_per_realm'], LD['atk_after']):.2f}</td></tr>" for i in range(10))
LADDER_HTML = f"""<h3>Thang vùng co giãn theo người chơi</h3>
  <p>Mức của mỗi vùng không cố định: server tự tính theo số lần chuyển sinh của người chơi đang hoạt động, để khi người chơi đã chuyển sinh nhiều (quá 10 lần), mọi vùng vẫn có người phù hợp thay vì cả server dồn vào bản đồ cuối.</p>
  <ul><li><b>Mẫu:</b> nhân vật chơi trong {LD['sample_days']} ngày gần nhất, cấp {LD['min_level']}+, mỗi tài khoản một nhân vật (nhiều chuyển sinh nhất), không tính bot / quản trị; dưới {LD['min_sample']} người thì giữ nguyên thang.</li>
    <li><b>Mức vùng r</b> = lớn nhất của: r (thang gốc) · số lần chuyển sinh ở phân vị của vùng ({', '.join(pct(p) for p in LD['percentiles'])} cho vùng 1 → 10) · mức vùng trước + 1. Mỗi lần tính lại (mỗi ngày lúc {LD['recompute_at']} giờ Việt Nam) mỗi vùng đổi tối đa ±{LD['max_step']}; không bao giờ dưới mức gốc. Quản trị có thể tính lại ngay, đóng băng hoặc đặt tay từng vùng.</li>
    <li><b>Quái:</b> bản đồ thứ n trong vùng đánh như mức vùng + {n(rl['depth_step'])} × (n − 1) như cũ, chỉ thay mức vùng gốc bằng mức hiện tại. Máu, thủ × (1 + {n(rl['mult_per_realm'])} × min(k, 10) + {n(LD['hp_after'])} × (k − 10)); công × (1 + {n(rl['atk_mult_per_realm'])} × min(k, 10) + {n(LD['atk_after'])} × (k − 10)); kinh nghiệm × (1 + {n(rl['xp_mult_per_realm'])} × min(k, 10) + {n(LD['xp_after'])} × (k − 10)); cấp hiện trên quái + 10 mỗi mức dời. Rơi đồ, ngọc theo mức mới (ngọc tối đa {pct(LD['jewel_max'])} / con).</li>
    <li><b>Sau mức 10 dốc nhỏ</b> vì người chơi sau chuyển sinh 10 mạnh lên rất chậm (+{R['character']['endless_points']} điểm, +{pct(R['character']['endless_hp_pct'])} máu mỗi lần): đồ tối đa, chuyển sinh 10 → 30 đánh vùng cùng mức đều khoảng 5 đòn thường / con, mất khoảng 5% máu mỗi đòn quái (scripts/realm_ladder/tune.exs).</li>
    <li><b>Người tụt hậu:</b> điều kiện vào vùng vẫn theo mức gốc; người chuyển sinh thấp hơn mức bản đồ thì công quái chỉ tính tới chuyển sinh của mình + {LD['underdog_margin']} (máu quái giữ nguyên): đánh lâu hơn nhưng không chết liên tục.</li>
    <li>Trên bản đồ và ở Chọn bản đồ, vùng đang dời ghi <b>≈ CS k</b>. Đổi thang thì báo kênh thế giới. Sự kiện theo phòng, đồ sát, đấu trường không theo thang này.</li></ul>
  <p class="note">Ví dụ: server 200 người, chuyển sinh rải đều 8–30. Ngày đầu mỗi vùng chỉ dời tối đa {LD['max_step']} mức; sau {_days} ngày thang ổn định:</p>
  <div class="scroll"><table><thead><tr><th>Vùng</th><th>Phân vị</th><th>Gốc</th><th>Ngày đầu</th><th>Ổn định</th><th>Máu / công quái (bản đồ 1)</th></tr></thead><tbody>{ladder_rows}</tbody></table></div>"""

# ---------- Bản đồ và quái ----------
def mrow(m):
    lv = "—" if not m["min"] else (f"{m['min']}" if m["min"] == m["max"] else f"{m['min']}–{m['max']}")
    mons = ", ".join(E(MON[k]["name"]) for k in m["monsters"] if k in MON and not MON[k]["boss"])
    bk = [k for k in m["monsters"] if k in MON and MON[k]["boss"]] + ([m["boss"]] if m.get("boss") in MON and m["boss"] not in m["monsters"] else [])
    boss = ", ".join(f"<b>{E(MON[k]['name'])}</b>" for k in bk)
    # như client (travelCost): Làng miễn phí; nơi khác base + per_level × cấp quái thấp nhất (không quái: 0)
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
SL, AR, GW = R["slay"], R["arena"], R["guild_war"]
REACHW = "theo cánh: không cánh đứng sát bên, cánh cấp 1 / 2 / 3 = " + " / ".join(str(x) for x in SL['reach_by_wing'][1:]) + " ô"
pk_items = [
    ("Đồ sát", f"tấn công người khác trên bản đồ chung, trong tầm {REACHW} (bấm là đánh ngay, không cần chạy sát bên; xa hơn thì chạy lại gần cho vào tầm; Biển Long Vương / Đồi Sáo Diều chỉ từ lúc báo {SL['event_pk']['warn_min']} phút trước khi Long Vương nổi / Chim Lạc tới cho tới lúc xuất hiện) (không ở {', '.join(E(MAPN.get(x, x)) for x in SL['safe_maps'])}), cả hai từ cấp {SL['min_level']}. Người kia đang đánh quái vẫn bị đánh ngay (trận đánh quái bị cắt ngang, quái giữ máu); chỉ không đánh được người đang trong trận đồ sát khác, và mình phải không đang trong trận. Luân phiên lượt, mỗi lượt {SL['turn_s']} giây, quá giờ server ra đòn thay bằng kỹ năng mạnh nhất còn dùng được. Thua (hết máu hoặc bỏ chạy) là gục như thường: mất {pct(R['character']['death_gold_loss'])} vàng đang mang, số vàng đó về tay người thắng."),
    ("Tên đỏ", f"thắng một người không tên đỏ thì bị tên đỏ {SL['red_s'] // 60} phút (cộng dồn). Người tên đỏ gục trong đồ sát mất vàng ×{SL['red_gold_mult']}. Hạ người tên đỏ thì không bị đỏ. Tự đánh tắt khi có người tên đỏ trên bản đồ."),
    ("Bảo vệ, giới hạn", f"vừa gục được bảo vệ {SL['protect_s']} giây (tự đi đồ sát thì mất bảo vệ); không giới hạn số lần đồ sát."),
    ("Đấu trường", f"đánh người khác do máy điều khiển (kỹ năng, thú cưng, buff, hồi máu của chính người đó), tối đa {AR['per_day']} trận mỗi ngày, điểm xếp hạng kiểu Elo (K = {AR['elo_k']}). "
                   f"Hạng theo số lần chuyển sinh ({', '.join(('CS ' + str(a) + '+') if b >= R['character']['max_rebirths'] else ('CS ' + str(a) + '–' + str(b)) for a, b in R['event_rooms']['bands'])}): chỉ thách đấu được người <b>cùng hạng hoặc hạng trên</b>, không thách nhân vật cùng tài khoản."),
    ("Chiến bang", f"bang chủ / phó bang tuyên chiến bang khác (bang kia nhận trong {GW['answer_s']} giây), kéo dài {GW['minutes']} phút. Mỗi trận Đấu trường thắng thành viên bang địch +1 điểm (cùng một đối thủ tính tối đa {GW['same_target_max']} lần). Bang nhiều điểm thắng: quỹ +{n(GW['win_fund'])}, thành viên có điểm nhận {n(GW['win_gold'])} vàng qua thư; hai bang chờ {GW['rematch_hours']} giờ mới chiến lại."),
]
# ---------- Thú cưng ----------
PR = R["pets"]
# thú hiếm (Long Vương): không bán, câu được ở Biển Long Vương (RULES.fishing.dragon)
DRG = R["fishing"]["dragon"]
def pet_price(pt):
    if not pt.get("rare"):
        return n(pt["price"])
    # Đồi Sáo Diều / Hắc Long (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long")
    if pt["id"] == R["sky"]["bird"]["pet"]:
        B = R["sky"]["bird"]
        return (f"🪁 thả diều ở Đồi Sáo Diều khi Chim Lạc lượn (mỗi giờ, {B['stay'] // 60} phút): trúng ô 1/{n(round(1 / B['chance']))}, "
                f"đầy Phong Khí + Sáo Đồng 1/{n(round(1 / (B['chance'] * (1 + B['phong_khi_max'] / B['phong_khi_div']) * B['bait_mult'])))}")
    if pt["id"] in (R["sky"]["egg"]["pet"], R["sky"]["egg"]["rare_pet"]):
        return f"🐉 ghép ở Lão Hỗn Nguyên từ Long Vương + Chim Lạc cấp tối đa (100%){' — ' + pct(R['sky']['egg']['rare_chance']) + ' ra Chân Thân' if pt['id'] == R['sky']['egg']['rare_pet'] else ''}"
    _k = 1 + DRG['long_khi_max'] / DRG['long_khi_div']
    return (f"🎣 câu ở {E(D['lake']['name'])} (cấp {D['lake']['min_level']}+) khi Ngài nổi (mỗi giờ một lần, {DRG['stay'] // 60} phút): "
            f"thả trúng ô Ngài 1/{n(round(1 / DRG['chance']))} mỗi lần, đầy Long Khí + Mồi Rồng 1/{n(round(1 / (DRG['chance'] * _k * DRG['bait_mult'])))}")
PET_GROUP = {"war": "⚔️ Chiến", "guard": "🛡️ Hộ vệ", "luck": "🍀 Tài lộc", "all": "🐉 Thần thú"}
pet_rows = "".join(
    f"<tr><td><b>{E(pt['name'])}</b></td><td>{PET_GROUP.get(pt['group'], pt['group'])}</td><td class=n>{pet_price(pt)}</td><td>{E(pt['desc'])}</td></tr>"
    for pt in sorted(D["pets"], key=lambda x: (x.get("rare", False), x["group"], x["price"])))
pet_rule = (f"Thú lên cấp theo trận thắng khi dắt theo (trùm tính {PR['boss_wins']} trận), cấp N cần {PR['xp_coef']} × N × (N − 1) trận, tối đa cấp {PR['max_level']} "
            f"({n(PR['xp_coef'] * PR['max_level'] * (PR['max_level'] - 1))} trận); phần trăm cộng × (1 + {pct(PR['bonus_per_level'])} × (cấp − 1)); máu / MP cộng số × cấp thú. "
            f"Cho ăn ở Người Nuôi Thú: {n(PR['feed_gold'])} × cấp² vàng được {PR['feed_xp']} trận. "
            + "".join(f"<b>{E(pt['name'])}</b> (thần thú độc nhất): cấp tối đa {pt['max_level']} ({n(PR['xp_coef'] * pt['max_level'] * (pt['max_level'] - 1))} trận), "
                      f"mỗi cấp +{pct(pt.get('per_level', PR['bonus_per_level']))} (cấp {pt['max_level']} ×{n(round(1 + (pt['max_level'] - 1) * pt.get('per_level', PR['bonus_per_level']), 2))}); "
                      + "; ".join(t for t in [
                          pt['traits'].get('ward') and f"Long Uy kháng {pct(pt['traits']['ward'])} hiệu ứng xấu",
                          pt['traits'].get('jewel') and f"ngọc rơi +{pct(pt['traits']['jewel'])}",
                          pt['traits'].get('boss') and f"thưởng trùm thế giới +{pct(pt['traits']['boss'])}",
                          pt['traits'].get('slayer') and f"Long Huyết: đánh Hắc Long / hệ Bóng Tối +{pct(pt['traits']['slayer'])}"] if t) + ". "
                      for pt in D["pets"] if pt.get("max_level")))
# Biển Long Vương: bảng cá riêng, Mồi Rồng (công thức của Bà Lang)
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
            f"Thú thuần (nhóm Chiến): công +{pct(PR['tame_bonus'])} + {pct(PR['tame_realm_bonus'])} × k, chí mạng +{pct(PR['tame_crit'])}.")
# DECISIONS "Người chơi trên bản đồ, Đồ sát nhanh": bấm người trên bản đồ, ⚡ Đồ sát nhanh
QK = R["quick"]
pk_items += [
    ("Người chơi trên bản đồ", "người khác vẽ trên bản đồ (hình mặc đồ, tên, tag bang; 🛡 đang được bảo vệ, ⚔ + máu khi đang đồ sát). "
     f"Bấm một người → menu Hồ sơ · Giao dịch · Mời tổ đội · 🗡 Đồ sát (nút mờ kèm lý do nếu không đánh được; trong tầm {REACHW} là đánh ngay); nhiều người cùng ô / có quái → bảng chọn. "
     "Không bấm là đánh ngay (tránh đồ sát nhầm). Cài đặt: Tất cả / Tổ đội & bang / Tắt (chỉ màn hình của mình; người đang đồ sát với mình và đồng đội luôn hiện); "
     "tab Quanh đây đủ danh sách, 📍 chỉ người đó trên bản đồ, 🗡 (🗡⚡ khi bật ⚡) ngay cạnh để đồ sát như trên bản đồ. Đồ sát không có màn VS / K.O.; người xong trận hết ngay dấu ⚔."),
    ("⚡ Đồ sát nhanh", f"đang bật ⚡ thì nút thành 🗡⚡ Đồ sát nhanh: trong tầm ({REACHW}) thì mở trận ngay (xa hơn chạy lại gần cho vào tầm), ở lại bản đồ; lượt của mình server đánh ngay theo combo ⚡ "
     f"(không chờ {SL['turn_s']} giây); ✋ cầm lại lượt. Luật đồ sát không đổi. Không bật ⚡: bảng trận như thường, mỗi lượt {SL['turn_s']} giây, hết giờ server đánh thay một đòn, "
     f"hết giờ {SL['max_timeouts']} lần liên tiếp thì thua."),
]
pk_li = "".join(f"<li><b>{k}</b>: {v}</li>" for k, v in pk_items)
_qcell = lambda on: "ở lại bản đồ, server đánh lượt của mình ngay theo combo" if on else f"bảng trận, tự bấm, {SL['turn_s']} giây / lượt"
pk_quick_rows = "".join(f"<tr><td>{'Bật ⚡' if a else 'Tắt ⚡'}</td><td>{'Bật ⚡' if b else 'Tắt ⚡'}</td><td>{_qcell(a)}</td><td>{_qcell(b)}</td></tr>"
                        for a in (True, False) for b in (True, False))
PK_QUICK = (f"""<h3>Ai đánh thế nào (mỗi bên theo ⚡ của chính mình)</h3>
  <div class="scroll"><table><thead><tr><th>Người tấn công</th><th>Người bị đánh</th><th>Màn người tấn công</th><th>Màn người bị đánh</th></tr></thead><tbody>{pk_quick_rows}</tbody></table></div>
  <p class="note">Bấm từ menu trên bản đồ: chạy tới cạnh rồi mở trận. Bấm từ Hồ sơ (Quanh đây → tên → Hồ sơ): mở trận ngay. Người tấn công luôn đi trước, đòn mở màn ×{n(SL['first_strike_mult'])}. """
            f"Người cùng bản đồ thấy ⚔ và máu trên đầu hai người đang đồ sát.</p>")

# ---------- Tự đánh, ⚡ Đánh nhanh (DECISIONS "Đánh nhanh theo combo") ----------
AU = R["auto"]
AUSK = {"all": "dùng bộ kỹ năng (buff trước)", "basic": "chỉ đòn thường", "boss": "kỹ năng chỉ với trùm / tinh anh / quái vàng / Bóng Đêm"}
AUKEEP = {"exc": "Excellent", "anc": "Đồ Thần", "luck": "May mắn / Kỹ năng", "opt": f"từ {AU['keep_opt_min']} dòng cộng thêm", "better": "tốt hơn đồ đang mặc", "cls": "mặc được (đúng lớp)"}
AMB = R["admin_max_build"]
TOOLS_HTML = f"""<h3>Thanh dưới bản đồ (một hàng)</h3>
  <p><b>🤖</b> Tự đánh và <b>⚡</b> Đánh nhanh là hai công tắc (sáng khi bật, tối khi tắt), dòng trạng thái, <b>🗑</b> Tự hủy đồ rơi (sáng khi bật, bấm mở cài đặt), <b>📜</b> nhật ký trận đánh nhanh vừa xong (cửa sổ nổi, cuộn được), <b>⚙</b> cài đặt của cả hai. Đang đánh nhanh: "⚡ Đang đánh … ❤ %" và ✋ Đánh tay.</p>
  <h3>⚙ Cài đặt (mỗi phần một nút 💾 Lưu; lưu không tự bật)</h3>
  <div class="grid2"><div class="card"><h3>🤖 Tự đánh</h3><ul>
    <li>Đánh: tất cả quái / quái không cao hơn mình (≤ cấp + 1) / một loại trên bản đồ.</li>
    <li>Phạm vi săn: {', '.join('cả bản đồ' if r == 0 else f'{r} ô quanh chỗ bật' for r in AU['range_options'])}.</li>
    <li>Kỹ năng: {'; '.join(AUSK.get(k, k) for k in AU['skills'])}.</li>
    <li>Đồ rơi: giữ hết, hoặc chỉ giữ: {', '.join(AUKEEP.get(k, k) for k in AU['keep'])} (ngọc, nguyên liệu, cánh, nhẫn, dây chuyền luôn giữ).</li>
    <li>Tự tắt khi hết bình máu, có người tên đỏ, bị đồ sát, gục ngã, rời bản đồ, đóng hết tab.</li></ul></div>
  <div class="card"><h3>⚡ Đánh nhanh</h3><ul>
    <li>Bật rồi tự bấm quái: đi tới, server đánh hết trận theo <b>combo</b>, ở lại bản đồ, xong trận đứng chờ (không tự tìm quái). Nhịp {QK['tick_ms']} ms / lượt.</li>
    <li>Combo tối đa {QK['max_steps']} bước (đòn thường, kỹ năng đang mang), danh sách ưu tiên: mỗi lượt duyệt từ bước 1, dùng bước đầu tiên dùng được (hết hồi chiêu, đủ MP), nên hết vòng tự quay lại kỹ năng đầu; chỉ đánh thường khi mọi bước đang hồi chiêu / thiếu MP; kỹ năng sẵn sàng mà chỉ thiếu MP thì uống mana. Bước buff có "chỉ khi chưa có hiệu ứng"; combo chưa lưu thì theo thứ tự bộ kỹ năng ô 1 → 5. Đòn thường nên để cuối. Đồ sát / đấu trực tiếp: kỹ năng của đối thủ bay về mình; đấu trực tiếp bật ⚡ đánh trên bản đồ như đồ sát nhanh.</li>
    <li>Sửa combo ở ⚙ hoặc Menu → Kỹ năng.</li></ul></div></div>
  <p><b>Chung cho cả hai</b>: uống bình máu khi dưới {AU['hp_pct']['default']}% (chỉnh {AU['hp_pct']['min']}–{AU['hp_pct']['max']}%), bình mana khi dưới {AU['mp_pct']['default']}% ({AU['mp_pct']['min']}–{AU['mp_pct']['max']}%).</p>
  <h3>Hiển thị khi đánh nhanh (ở lại bản đồ)</h3>
  <ul><li>Con đang đánh: nhãn ⚔, thanh máu theo lượt, số sát thương / máu hồi bay lên trên đầu quái và mình; hiệu ứng kỹ năng theo hệ, đòn thường, trượt, buff, quái đánh trúng (kỹ năng quái: hạt màu hệ), quái gục, cột sáng đồ rơi như màn trận (theo công tắc Hiệu ứng động).</li>
    <li>Xong trận: thông báo "⚡ Hạ …: +EXP, +vàng, N món rơi, 🗑 hủy N món"; 📜 xem lại nhật ký.</li>
    <li>Dùng được ở bản đồ thường, Động Bí Ẩn, Tháp và sự kiện có tầng riêng (con đang đánh vẫn vẽ dù tạm vắng khỏi danh sách tầng). Đấu trường (bản sao) cũng tự đánh lượt theo combo ở màn trận; đồ sát xem ⚡ Đồ sát nhanh ở mục PK.</li></ul>
  <h3>Bật cả 🤖 và ⚡</h3>
  <p>Tự đánh tự tìm quái nhưng đánh theo combo ⚡ và ở lại bản đồ (không mở bảng đánh quái); thanh: "🤖 đã hạ N · ⚡ Đang đánh … ❤ %".</p>
  <h3>Tự hủy đồ rơi</h3>
  <p>Menu → Cài đặt: món trang bị rơi không thuộc loại đã chọn bị hủy ngay, không vào túi; áp cho mọi trận (đánh tay, Tự đánh, Đánh nhanh).</p>
  <h3>Tiện ích khác</h3>
  <ul><li>Tháo / mặc / ép đồ giữ tỉ lệ máu; ngoài trận máu / mana không vượt mức tối đa.</li>
    <li>Bản đồ thu nhỏ: giữ và kéo để dời chỗ (nhớ vị trí), bấm nhẹ mở bản đồ thế giới. Chấm: trắng nhấp nháy là mình, hồng người chơi khác, vàng chanh đồng đội, xanh dương bang mình, cam viền trắng bang địch; quái đỏ, NPC xanh lá, cổng tím.</li>
    <li>👫 Quanh đây có tab <b>🟢 Đang online</b>: mọi người đang online (kèm bản đồ họ đứng), chạm tên mở hồ sơ như Quanh đây.</li>
    <li>Nhật ký đồ sát: dòng của đối thủ chi tiết như dòng của mình (tên, chiêu, ⚔ sát thương, máu còn lại); trúng độc / bỏng / chảy máu ghi rõ máu mỗi lượt, số lượt.</li></ul>
  <h3>Quản trị: ⚡ Dựng nhân vật tối đa</h3>
  <p>Tab Quản trị → tra cứu người chơi → chọn cấp, số lần chuyển sinh (0–999; điểm tiềm năng tự tính theo cấp / chuyển sinh rồi tự cộng hết, đủ chỉ số yêu cầu của đồ trước), Excellent / Đồ Thần, tay trái vũ khí / khiên, mặc luôn (túi đầy thì món bị thay ra gửi Hộp thư giữ +N), vàng {n(AMB['gold'])}, vật phẩm (cả đồ thả diều), thần thú {E(', '.join(next((x['name'] for x in D['pets'] if x.get('id') == i), i) for i in AMB['pets']))} cấp tối đa (dắt con cuối), đầy Long Khí / Phong Khí; chọn nhẫn / dây chuyền (có món kháng hệ). Đồ tốt nhất của lớp +{AMB['up']}, {AMB['opt']} dòng, May mắn; kỷ lục tháp {AMB['tower_floor']}, thông thạo kỹ năng {AMB['mastery']}.</p>
"""

# ---------- Sự kiện, đấu trường, chiến bang trực quan (DECISIONS cùng tên) ----------
CSR = R["castle_siege"]
EVVIZ_HTML = f"""<h3>Thanh sự kiện (mép trên bản đồ)</h3>
  <p>Một dòng mỗi việc, có thanh tiến độ và đồng hồ đếm ngược; bản đồ nhỏ tự dời xuống dưới thanh.</p>
  <div class="scroll"><table><thead><tr><th>Nơi</th><th>Thanh hiện</th></tr></thead><tbody>
    <tr><td>Quảng Trường Quỷ</td><td>🌊 Đợt n/{len(R['devil_square']['waves'])} · điểm · còn quái / cầu thang mở · giờ còn</td></tr>
    <tr><td>Lâu Đài Máu</td><td>🛡 Quân canh k/{R['blood_castle']['guards']} → 🚪 Phá Cổng Thành (máu cổng) → 🩸 Hạ Hiệp Sĩ Máu</td></tr>
    <tr><td>Kalima</td><td>👹 Quái Kalima k/n → 👹 Hạ Kundun</td></tr>
    <tr><td>Phòng đánh chung</td><td>thêm 👥 số người cùng phòng (người cùng phòng vẽ trên bản đồ)</td></tr>
    <tr><td>Hỗn Chiến Thành</td><td>⏳ Hỗn chiến sau … · số người → ⚔ Còn N người · M quái</td></tr>
    <tr><td>Công Thành Chiến</td><td>👑 [bang] giữ Vương Miện (bang mình: "bảo vệ nó!") / chưa có chủ / đang hiện lại · giờ còn</td></tr>
    <tr><td>Tế Đàn (Cổ Long)</td><td>🐉 máu % · số người đánh · giờ còn + top 3 sát thương (★ là mình, hạng 4–5 thêm "★ #4"); chưa xuất hiện: "xuất hiện sau …"</td></tr>
    <tr><td>Chiến bang (mọi bản đồ, trừ Tháp)</td><td>⚔ [MÌNH] a – b [ĐỊCH] · giờ còn (thanh xanh / đỏ)</td></tr>
  </tbody></table></div>
  <p>Băng rôn giữa màn khi sang đợt / bước mới (Cổng Thành vỡ, Hiệp Sĩ Máu, Kundun xuất hiện, hoàn thành) và khi Hỗn Chiến Thành bắt đầu.</p>
  <h3>Trên bản đồ</h3>
  <ul><li><b>Cổ Long</b>: quầng đỏ nhấp nháy, thanh máu to có %; bật ⚡ rồi chạm là đánh ngay trên bản đồ (số bay lên chỉ là sát thương của mình).</li>
    <li><b>Vương Miện</b> (Công Thành, ô {CSR['crown']['at'][0]}, {CSR['crown']['at'][1]}): quầng vàng + 👑; khuất thì mũi tên vàng ở mép chỉ hướng. Mỗi bang một màu vòng dưới chân, bang giữ Vương Miện vàng + 👑 trước tên.</li>
    <li><b>Chiến bang</b>: người bang địch vòng đỏ nhấp nháy, ⚔ trước tên.</li>
    <li><b>Bản đồ nhỏ</b>: Cổ Long (đỏ, to), Vương Miện (vàng), người chơi khác (hồng), đồng đội (vàng chanh), bang mình (xanh dương), bang địch (cam viền trắng).</li></ul>
  <h3>Chạm là đánh</h3>
  <p>Đang hỗn chiến (Hỗn Chiến Thành: ai cũng là đối thủ) hoặc Công Thành Chiến (người bang khác, ưu tiên bang đang giữ Vương Miện): chạm người là đồ sát ngay, không mở menu; bật ⚡ thì ở lại bản đồ.</p>
  <h3>Chiến bang khi đồ sát</h3>
  <p>Hai bang đang chiến: đồ sát thành viên bang địch trên bản đồ (bên nào thắng cũng được) <b>+1 điểm</b> cho bang người thắng (mỗi cặp tối đa {GW['same_target_max']} lần, chung với đấu trường), người thắng <b>không bị tên đỏ</b>; vàng mất / nhận và bảo vệ như đồ sát thường. Thắng chiến bang: quỹ +{n(GW['win_fund'])}, ai ghi điểm nhận {n(GW['win_gold'])} vàng.</p>
  <h3>Đấu trường</h3>
  <ul><li>Thách đấu bản sao: màn <b>VS</b> chiếu xong (2 giây) trận mới bắt đầu (bấm đánh lúc đó thì chờ hết màn); <b>K.O.</b> hiện sau đòn cuối, khi trận đã xong hẳn. Đồ sát và đấu trực tiếp không có VS / K.O.</li>
    <li>Thách đấu bản sao, bật ⚡: server tự đánh từng lượt theo combo (thanh "⚡ Đang đánh theo combo", ✋ Đánh tay).</li>
    <li><b>⚔ Đấu trực tiếp</b> (menu người trên bản đồ, hồ sơ): người kia nhận trong {AR['duel_invite_s']} giây; mời từ bản đồ nào cũng được, nhận thì cả hai được đưa tới hai đầu <b>{E(DUELN)}</b>, tự đi lại gần trong tầm đánh (theo cánh) rồi bấm Đồ sát nhau ({AR['duel_map']['wait_s']} giây không đánh thì về chỗ cũ); xong trận (thắng, thua, bỏ chạy, hủy) về đúng chỗ cũ; luân phiên lượt {SL['turn_s']} giây như đồ sát (⚡ tự đánh lượt ở màn trận). Vào trận đầy máu, xong trả lại máu cũ; không chết, không mất vàng, không tên đỏ; bỏ chạy = thua. Điểm đấu trường đổi như thách đấu (K = {AR['elo_k']}), tính vào {AR['per_day']} trận / ngày của người mời; thắng thành viên bang địch +1 điểm chiến bang.</li></ul>
"""


# ---------- Sự kiện & PK: chơi ở đâu đánh người được, luật từng nơi (bảng anh yêu cầu 2026-11-08) ----------
CH, DSQ, BCQ, CCQ, KAQ, INV, RAIDS, SEC, WBC = R["character"], R["devil_square"], R["blood_castle"], R["chaos_castle"], R["kalima"], R["invasion"], R["raids"], R["secret"], D["world_boss"]


def _sched(every_h, off_min=0):
    def hm(m):
        h, mm = divmod(m % (24 * 60), 60)
        return f"{h}h{mm:02d}" if mm else f"{h}h"
    xs = [hm(off_min + every_h * 60 * i) for i in range(24 // every_h)]
    return f"{xs[0]}, {xs[1]} … {xs[-1]}" if len(xs) > 3 else ", ".join(xs)


_WEEK = {1: "thứ Hai", 2: "thứ Ba", 3: "thứ Tư", 4: "thứ Năm", 5: "thứ Sáu", 6: "thứ Bảy", 7: "Chủ Nhật"}
_YES, _NO = '<b style="color:#c0392b">✅ Có</b>', '<b style="color:#2e7d32">❌ Không</b>'
_normal = "Luật đồ sát thường (mất vàng, tên đỏ)."
BMR = R["blood_moon"]
pk_rows = [
    ("Golden Invasion", f"Mỗi {INV['every_hours']} giờ ({_sched(INV['every_hours'])}), {INV['minutes']} phút, bản đồ đầu mỗi vùng + {R['starter_events']['realm_pick']} bản đồ vùng chuyển sinh ({R['starter_events']['invasion_count']} quái vàng, không trùm vàng)", _YES, _normal + " Người đang đánh quái vàng vẫn bị đồ sát.", f"Thêm {R['starter_events']['realm_pick']} bản đồ vùng chuyển sinh ngẫu nhiên mỗi đợt (quái mạnh như vùng đó); ở bản đồ đầu vùng, trùm chỉ rơi ngọc cho người dưới chuyển sinh {R['starter_events']['jewel_max_rebirths']}."),
    *[(RAIDS[k]["name"], f"Mỗi {RAIDS[k]['every_hours']} giờ ({_sched(RAIDS[k]['every_hours'], RAIDS[k]['offset_minutes'])}), {RAIDS[k]['minutes']} phút, {RAIDS[k]['pick']} bản đồ vùng ngẫu nhiên + {R['starter_events']['realm_pick']} bản đồ vùng chuyển sinh", _YES, _normal, f"Thêm {R['starter_events']['realm_pick']} bản đồ vùng chuyển sinh ngẫu nhiên mỗi đợt (quái mạnh như vùng đó); ở bản đồ đầu vùng, trùm chỉ rơi ngọc cho người dưới chuyển sinh {R['starter_events']['jewel_max_rebirths']}.") for k in RAIDS if not k.startswith("_")],
    ("Trùm thế giới Cổ Long (Tế Đàn)", f"Lần đầu sau {WBC['first_after_minutes']} phút, rồi mỗi {WBC['every_minutes']} phút (tính từ khi con trước gục / bay đi), {WBC['duration_minutes']} phút, cả server đánh chung; máu {n(WBC['hp'])} + {n(R['world_boss']['hp_per_fighter'])} mỗi người mới vào đánh trong {R['world_boss']['grow_minutes']} phút đầu (tối đa {n(R['world_boss']['hp_cap'])}); gây ≥ {pct(R['world_boss']['join_min_share'])} máu: +" + ", ".join(f"{v} {E(IT[k]['name'])}" for k, v in R['world_boss']['join_items'].items()), _YES + " (Tế Đàn không phải vùng an toàn)",
     _normal + " Người đang đánh Cổ Long bị đồ sát thì trận với trùm bị cắt; sát thương đã gây vẫn tính thưởng.",
     "Thanh máu to + %, top 3 sát thương (★ mình); bật ⚡ chạm là đánh ngay trên bản đồ (đứng ngoài bản đồ nên dễ bị thấy, bị đồ sát hơn)."),
    ("Quảng Trường Quỷ", f"Mỗi {DSQ['every_hours']} giờ ({_sched(DSQ['every_hours'], DSQ['offset_hours'] * 60)}), vào trong {DSQ['entry_minutes']} phút, chơi {DSQ['run_minutes']} phút, cấp {DSQ['min_level']}+, vé", _NO, "Bản đồ riêng theo phòng (chia theo số lần chuyển sinh).", f"Thanh 🌊 Đợt n/{len(DSQ['waves'])} · điểm · giờ còn; băng rôn sang đợt; 👥 số người cùng phòng."),
    ("Lâu Đài Máu", f"Mỗi {BCQ['every_hours']} giờ ({_sched(BCQ['every_hours'], BCQ['offset_minutes'])}), vào {BCQ['entry_minutes']} phút, chơi {BCQ['run_minutes']} phút, cấp {BCQ['min_level']}+, vé", _NO, "Bản đồ riêng theo phòng.", f"Thanh quân canh k/{BCQ['guards']} → phá Cổng Thành → Hiệp Sĩ Máu; băng rôn mỗi bước."),
    ("Kalima", f"Lúc nào cũng vào, {KAQ['run_minutes']} phút, cấp {KAQ['min_level']}+, Bản Đồ Thất Lạc", _NO, "Bản đồ riêng theo tổ đội.", f"Thanh quái k/{KAQ['guards']} → Kundun; băng rôn."),
    ("Tháp Vô Tận", "Lúc nào cũng vào", _NO, "Bản đồ riêng.", "—"),
    ("Hỗn Chiến Thành", f"Mỗi {CCQ['every_hours']} giờ ({_sched(CCQ['every_hours'], CCQ['offset_minutes'])}), vào {CCQ['entry_minutes']} phút rồi hỗn chiến {CCQ['run_minutes']} phút, cấp {CCQ['min_level']}+, vé",
     _YES + ", chỉ khi đã vào giờ hỗn chiến",
     f"Ai cũng đánh ai (không cần khác bang). <b>Không mất vàng, không tên đỏ</b>; gục là bị loại, về Làng. Mỗi người hạ +{n(CCQ['reward']['per_player_kill'])} vàng thưởng; trụ cuối cùng {n(CCQ['reward']['winner']['gold'])} vàng + ngọc.",
     "<b>Chạm người là đồ sát ngay</b> (không menu); bật ⚡ ở lại bản đồ, server đánh lượt theo combo. Thanh ⚔ Còn N người · M quái, băng rôn hỗn chiến bắt đầu."),
    ("Công Thành Chiến", f"{_WEEK.get(CSR['weekday'], CSR['weekday'])} {CSR['hour']}h{CSR['minute']:02d}, {CSR['run_minutes']} phút, cấp {CSR['min_level']}+, bang đăng ký ({n(CSR['register_gold'])} vàng)",
     _YES + ", chỉ người <b>khác bang</b>, trong lúc đánh",
     "<b>Không mất vàng, không tên đỏ</b>; cùng bang không đánh nhau. Bang giữ Vương Miện không đánh được nó (phải chặn bang khác). Gục về Làng, vào lại được.",
     "<b>Chạm người bang khác là đồ sát ngay</b> (ưu tiên bang giữ Vương Miện); Vương Miện 👑 phát sáng + mũi tên khi khuất; mỗi bang một màu vòng chân; thanh 👑 [bang] giữ · giờ còn."),
    ("Động Bí Ẩn", f"Ban đêm, mở {pct(SEC['open_chance'])} số đêm; trùm {SEC['boss_from_h']}h–{SEC['boss_to_h']}h", _YES, _normal + " Động tối, khó thấy người tới.", "Người chơi vẽ trên bản đồ + chấm hồng ở bản đồ nhỏ: dễ phát hiện hơn."),
    ("Biển Long Vương, Đàn Cá Vàng", "Theo giờ", f"Chỉ từ lúc báo {R['slay']['event_pk']['warn_min']} phút trước khi Long Vương nổi tới lúc Ngài nổi; ngoài khung đó là vùng an toàn", _normal + " Người đang câu cá cũng bị đánh.", "Bản đồ 44×26: làng chài, vịnh, mũi cát có ghềnh đá, 5 cầu tàu, sóng dạt bờ (vẽ liền mạch)."),
    ("Đồi Sáo Diều (Chim Lạc, Đàn Hạc, mưa sao băng)", f"Chim Lạc mỗi {R['sky']['bird']['every'] // 3600} giờ ({R['sky']['bird']['stay'] // 60} phút), Đàn Hạc ~{R['sky']['flock']['every'] // 60} phút, sao băng ban đêm; cấp 30+", _YES, _normal + " Người đang thả diều cũng bị đánh.", "Mới: bản đồ thả diều cạnh Biển Long Vương."),
    ("Pháp Trường Huyết Nguyệt", f"Quản trị mở ({BMR['minutes']} phút mặc định, 1–{BMR['minutes_max']}) hoặc lịch hằng ngày, báo trước {BMR['warn_min']} phút; cổng phía nam Làng, cấp {D['bm_map']['min_level']}+",
     _YES + ", chỉ lúc trăng mọc (ngày thường an toàn)",
     f"Ai cũng đánh ai, kể cả cùng tổ đội (trận bắt đầu lúc trăng mọc vẫn theo luật này dù trăng lặn giữa trận). <b>Không mất vàng, không tên đỏ</b>; gục về Làng, {BMR['relock_s']} giây sau mới vào lại. Hạ người: {pct(BMR['drop_pct'])} cơ hội rơi 1 viên ({', '.join(E(IT[j]['name']) for j in BMR['jewels'])}), "
     f"× (1 + {n(BMR['rebirth_step'])} × số lần chuyển sinh người gục hơn mình), chặn 0 – ×{n(BMR['rebirth_max'])}; hạ lại cùng người mỗi lần ×{n(BMR['repeat_decay'])}. Hạ bot / bot hạ chỉ tính điểm, không rơi ngọc. "
     f"Trăng lặn: top {len(BMR['top_rewards'])} người thật (≥ {BMR['min_kills']} mạng) nhận ngọc qua thư, mặc định " + "; ".join(f"hạng {i + 1}: " + ", ".join(f"{v} {E(IT[k]['name'])}" for k, v in rw.items()) for i, rw in enumerate(BMR['top_rewards'])) + " (Quản trị chỉnh được).",
     f"Mới: điểm theo chênh chuyển sinh; 🩸 Huyết Sát (hạ {BMR['streak']['min']} người liên tiếp, ai hạ được +{BMR['streak']['bounty_points']} điểm, ngọc ×{n(BMR['streak']['bounty_drop_mult'])}); 🔥 Bàn thờ Huyết Ngọc giữa sân (đứng một mình {BMR['altar']['hold_s']} giây nhận ngọc); bản đồ 60×40 không quái, trăng máu; dải 🩸 giờ / điểm / hạng + top 3, 🏆 top 10; Quản trị gọi tất cả bot vào."),
    ("Bản đồ vùng, vùng chuyển sinh", "—", _YES, _normal, "—"),
    ("Làng", "—", _NO, "Vùng an toàn.", "—"),
]
pk_ev_rows = "".join(f"""<div class="card"><h3>{a}</h3><p><b>PK:</b> {c}</p>{'' if b == '—' else f'<p class="note"><b>Lịch:</b> {b}</p>'}<p><b>Luật:</b> {d}</p>{'' if e == '—' else f'<p class="note"><b>Mới:</b> {e}</p>'}</div>""" for a, b, c, d, e in pk_rows)
_arena = [
    ("Đối thủ", "Bản sao chỉ số (máy đánh), người kia không cần online", f"Người thật, phải online và bấm nhận trong {AR['duel_invite_s']} giây"),
    ("Bản đồ", "Ở đâu cũng được", f"Mời từ bản đồ nào cũng được (kể cả Làng); nhận thì cả hai tới hai đầu {E(DUELN)}, tự đi lại gần rồi đánh, xong về chỗ cũ"),
    ("Máu", "Máu hiện có", "Vào trận đầy máu, xong trả lại máu như trước"),
    ("Thua", f"Mất {pct(CH['death_gold_loss'])} vàng, về Làng; bỏ chạy không mất gì", "<b>Không chết, không mất vàng</b>; bỏ chạy tính thua"),
    ("Tên đỏ", "Không", "Không"),
    ("Điểm đấu trường (Elo)", f"Có (K = {AR['elo_k']}), tối đa {AR['per_day']} trận / ngày", f"Có, như thách đấu; tính vào {AR['per_day']} trận / ngày của <b>người mời</b>"),
    ("Chiến bang", "Người thách đấu thắng thành viên bang địch: +1 điểm", "Ai thắng thành viên bang địch: +1 điểm"),
    ("⚡ Đánh nhanh", "Server tự đánh từng lượt theo combo (màn trận)", f"Server tự đánh lượt theo combo (màn trận); không bật thì {SL['turn_s']} giây / lượt"),
    ("Hiển thị", "Màn VS chiếu xong mới đánh, K.O. sau khi trận xong", "Không VS / K.O., nhãn ⚔ Đấu trường trực tiếp"),
]
arena_rows = "".join(f"<tr><td><b>{a}</b></td><td>{b}</td><td>{c}</td></tr>" for a, b, c in _arena)
PKEV_HTML = f"""<h3>Luật đồ sát chung</h3>
  <ul><li><b>Ở đâu:</b> chỉ trên bản đồ dùng chung, không phải vùng an toàn ({', '.join('Làng' if m == 'village' else m for m in SL['safe_maps'])}). Tháp và sự kiện theo phòng là bản đồ riêng: không đánh người được.</li>
    <li><b>Điều kiện:</b> cùng bản đồ, cùng từ cấp {SL['min_level']}. Người tấn công phải rảnh tay; người bị đánh đang đánh quái vẫn bị kéo vào trận (quái nhả ra, giữ máu).</li>
    <li><b>Đánh:</b> luân phiên lượt {SL['turn_s']} giây; quá giờ server đánh thay, quá {SL['max_timeouts']} lần liên tiếp thì thua. Đòn mở màn người tấn công ×{n(SL['first_strike_mult'])}.</li>
    <li><b>Sát thương lên người</b> ×{n(PV['dmg_mult'])}, tỉ lệ chí mạng ×{n(PV['crit_rate_mult'])}, né ×{n(PV['dodge_mult'])}; mỗi lớp nhận theo hệ số riêng.</li>
    <li><b>Thua</b> (kể cả bỏ chạy): mất {pct(CH['death_gold_loss'])} vàng (về tay người thắng), về Làng, được bảo vệ {SL['protect_s']} giây.</li>
    <li><b>Tên đỏ:</b> hạ người không tên đỏ thì đỏ {SL['red_s'] // 60} phút (cộng dồn); tên đỏ gục mất {pct(CH['death_gold_loss'] * SL['red_gold_mult'])} vàng; hạ người tên đỏ không bị đỏ.</li></ul>
  <h3>Từng sự kiện</h3>
  <p class="note">Tóm tắt — đánh người được: {', '.join(r[0] for r in pk_rows if r[2].startswith(_YES))}. Không: {', '.join(r[0] for r in pk_rows if r[2] == _NO)}.</p>
  <div class="grid2">{pk_ev_rows}</div>
  <h3>Chiến bang</h3>
  <ul><li><b>Điểm:</b> thắng thành viên bang địch ở đấu trường +1; <b>mới:</b> đồ sát thành viên bang địch trên bản đồ +1 (bên nào thắng cũng được). Mỗi cặp tối đa {GW['same_target_max']} lần, chung giới hạn đấu trường và đồ sát.</li>
    <li><b>Mới:</b> đồ sát người bang địch lúc đang chiến <b>không bị tên đỏ</b>; vàng mất / nhận và bảo vệ {SL['protect_s']} giây như thường. Không áp trong Hỗn Chiến Thành, Công Thành (luật riêng).</li>
    <li>Trận kéo dài {GW['minutes']} phút. Thắng: quỹ bang +{n(GW['win_fund'])}, ai ghi điểm nhận {n(GW['win_gold'])} vàng. Hai bang chiến lại sau {GW['rematch_hours']} giờ.</li>
    <li><b>Hiển thị mới:</b> người bang địch vòng đỏ nhấp nháy + ⚔ trước tên, thanh tỉ số [MÌNH] a – b [ĐỊCH] mọi bản đồ (trừ Tháp), chấm cam ở bản đồ nhỏ.</li>
    <li><b>Tác động:</b> chiến bang thành PK thật trên bản đồ, không chỉ đánh bản sao ở đấu trường; bang đông người online, chủ động đi săn có lợi.</li></ul>
  <h3>Đấu trường: thách đấu và ⚔ đấu trực tiếp</h3>
  <div class="scroll"><table><thead><tr><th></th><th>Thách đấu (bản sao)</th><th>⚔ Đấu trực tiếp (mới)</th></tr></thead><tbody>{arena_rows}</tbody></table></div>
  <p class="note">Đấu trực tiếp là "đấu tập" không mất gì nhưng vẫn đổi điểm đấu trường; giới hạn {AR['per_day']} trận / ngày của người mời hạn chế đẩy điểm qua lại. Tab 🟢 Đang online (Quanh đây) thấy người ở mọi bản đồ để mời đấu trực tiếp; đồ sát vẫn phải cùng bản đồ.</p>
"""


# ---------- Đồi Sáo Diều, Chim Lạc, Hắc Long (DECISIONS cùng tên) ----------
SKR = R["sky"]
_pet = {x["id"]: x for x in D["pets"]}
_iname = lambda i: E(IT[i]["name"]) if i in IT else i
_pool = lambda pool: ", ".join(f"{_iname(i)} {pct(w / sum(x[0] for x in pool))}" for w, i in pool)
SKY_HTML = f"""<p>Bản đồ <b>Đồi Sáo Diều</b> (cổng mép phải Biển Long Vương, từ cấp {D['sky_map']['min_level'] if 'sky_map' in D else 30}): đứng chỗ thoáng trên đồi (không sát cây), chạm vào khoảng trời chỗ nào cũng được (dây diều không giới hạn), hoặc bấm 🪁 Thả diều: diều lên giữa trời, cao hơn mép đồi {SKR['aim']['rise'][0]}–{SKR['aim']['rise'][1]} ô, lệch tối đa {SKR['aim']['spread']} cột (khung nhìn tự nâng lên, thu nhỏ nhẹ cho thấy cả diều lẫn người). Gió giật sau {SKR['wait_ms'][0] // 1000}–{SKR['wait_ms'][1] // 1000} giây, giữ dây trong {SKR['window_ms'] / 1000:g} giây thì được quà gió, +1 Phong Khí (tối đa {SKR['bird']['phong_khi_max']}).</p>
  <div class="grid2">
    <div class="card"><h3>Quà gió</h3><p class="note">Thường: {_pool(SKR['pool'])}.</p><p class="note">🕊 Đàn Hạc (~{SKR['flock']['every'] // 60} phút một lần, {SKR['flock']['stay'] // 60} phút): {_pool(SKR['flock']['pool'])}; +{SKR['flock']['phong_khi']} Phong Khí.</p></div>
    <div class="card"><h3>🐦 Chim Lạc</h3><p class="note">Lượn mỗi {SKR['bird']['every'] // 3600} giờ ở một ô trời, {SKR['bird']['stay'] // 60} phút. Thả trúng ô đó: 1/{round(1 / SKR['bird']['chance']):,} × (1 + Phong Khí / {SKR['bird']['phong_khi_div']}) × {SKR['bird']['bait_mult']} nếu có {_iname(SKR['bird']['bait'])} (chỉ tốn khi trúng). Đã có thì được {SKR['bird']['dupe_n']} {_iname(SKR['bird']['dupe'])}.</p><p class="note">{E(_pet['chim_lac']['desc'])}</p></div>
    <div class="card"><h3>🌠 Mưa sao băng</h3><p class="note">Ban đêm mỗi {SKR['meteor']['every'] // 60} phút rơi {SKR['meteor']['count']} {_iname(SKR['meteor']['item'])} trên đồi, ở {SKR['meteor']['stay'] // 60} phút; chạm để đi tới nhặt, ai tới trước được.</p></div>
    <div class="card"><h3>🪁 Ông Lão Làm Diều</h3><p class="note">Việc mỗi ngày: thả thành công {SKR['elder']['count']} lần ở đồi → vàng, kinh nghiệm, +{SKR['elder']['phong_khi']} Phong Khí. Ghép {_iname('sao_dong')}: {', '.join(f'{n} {_iname(i)}' for i, n in SKR['craft']['sao_dong'].items())}.</p></div>
  </div>
  <h3>🐉 Hắc Long — Con Rồng Cháu Tiên</h3>
  <p>Long Vương (Lạc Long Quân, dưới nước) và Chim Lạc (Âu Cơ, trên trời) kết duyên sinh Hắc Long. <b>Ghép ở Lão Hỗn Nguyên</b> (Làng): có cả hai con <b>cấp tối đa</b> → tỉ lệ 100%, mất cả hai thú, nhận Hắc Long ({pct(SKR['egg']['rare_chance'])} ra Hắc Long Chân Thân); đã có Hắc Long thì con mới vào túi dạng Ấn. Long Phượng Hội đã bỏ.</p>
  <p><b>Thú thành vật phẩm</b>: mọi thú đóng ấn được ở tab Thú cưng (📦 Đóng ấn → món "Ấn &lt;tên&gt; · cấp N" trong túi, giữ cấp), bán ở chợ / giao dịch; mở ấn ở túi đồ khi chưa có con cùng loại. Câu / thả diều được Long Vương, Chim Lạc khi đã có thì con mới vào túi dạng Ấn (không còn đền bù Cá Chép Vàng / Mảnh Sao).</p>
  <div class="scroll"><table><thead><tr><th>Thú</th><th>Chỉ số (cấp 1; mỗi cấp +8 %, tối đa 30)</th></tr></thead><tbody>
    {''.join(f"<tr><td><b>{E(_pet[i]['name'])}</b></td><td>{E(_pet[i]['desc'])}</td></tr>" for i in ['long_vuong', 'chim_lac', 'hac_long', 'hac_long_chan'] if i in _pet)}
  </tbody></table></div>
  <p class="note">Cân bằng (thú cấp 30, Kiếm Sĩ 10 lần chuyển sinh): Hắc Long chỉ nhỉnh hơn Long Vương một chút (công +3 %, thủ +2 %, máu +4 %, thêm chí mạng / né); Chim Lạc thiên chí mạng, né, máu, kinh nghiệm / vàng (không cộng công / thủ). Long Huyết: đánh Hắc Long và quái hệ Bóng Tối +10 % (Chân Thân +15 %).</p>
  <p class="note">Dắt Hắc Long vào trận với trùm cuối Hắc Long: nhật ký có thoại riêng ("Đồng tộc phản bội!…"). Màn đăng nhập ghi tên <b>người đầu tiên của server thuần phục Hắc Long</b> dưới hình rồng; người đó cũng được báo cả server.</p>
"""

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
    ("MP kỹ năng", f"số MP trong bảng là ở cấp 1; tốn = MP × (1 + {n(C['skill_mp_per_level'])} × (cấp − 1)), cộng thẳng, không lũy thừa. Mọi kỹ năng (lớp và tháp) nhân thêm theo lớp: " + ", ".join(f"{CL[c]['name']} ×{n(v)}" for c, v in R['tower_skills'].get('mp_mult', {}).items()) + " (lớp khác ×1)."),
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
    ("Thú nuôi", f"ô thú nuôi đeo thú cưng (mua, hoặc thuần hóa loại quái đã hạ {R['pets']['tame_kills']} con); thú cộng % chỉ số (máu / MP cộng số theo cấp thú), không đánh trong trận."),
    ("Nhiều nhân vật", f"mỗi tài khoản tối đa {R['account']['max_characters']} nhân vật, một nhân vật online một lúc. <b>Thủ Kho</b> (đồ thường, đồ hiếm kèm cấp ép, vàng, chỗ mở rộng) dùng chung cả tài khoản; Rương Gia Truyền và quà quản trị gửi mọi người mỗi tài khoản một phần. Bạn bè, bang, thư, chợ, đồ sát, đấu trường tính riêng từng nhân vật; xóa nhân vật thì đồ trên nhân vật đó mất hẳn."),
    ("Đá Dịch Chuyển (ô W)", "Đài Phúc Lành và Rương Gia Truyền đã bỏ: chạm ô W chỉ ghi nhận Đá Dịch Chuyển của bản đồ, không ban phúc, gục ngã thì về Làng."),
    ("Bot (người chơi máy)", f"ép đồ như người thật khi dư vàng (giữ lại {R['bots']['forge']['gold_keep_per_level']} × cấp vàng mua bình): +1 → +9 món đang mặc cấp thấp nhất trước, từ +7 chỉ khi dư {R['bots']['forge']['spare']} viên ngọc; thêm dòng Ngọc Sinh Mệnh cho vũ khí, áo giáp; ghép / nâng cánh; +10 / +11 khoảng 1/{R['bots']['forge']['daring_every']} số bot, từ chuyển sinh {R['bots']['forge']['chaos_from_rebirths']} thì mọi bot. <b>Rèn đi trước chuyển sinh và sự kiện</b>: có ngọc, dư vàng là về Làng ép. Cấp tối đa thì chuyển sinh (tới CS {R['bots']['max_rebirths']}, tối đa {R['character']['rebirth_per_day']} lần/ngày), cần chúa tể thì đi vùng chuyển sinh săn; còn lại luyện ở vùng hợp sức theo thang vùng (mức ≤ CS + {R['bots']['ladder_margin']}). <b>Săn Hắc Long</b>: từ chuyển sinh {R['bots']['hac']['min_rebirths']}, chưa có Hắc Long thì Long Vương nổi hay Chim Lạc lượn đều đi săn; có con nào chưa cấp tối đa thì dắt con đó, cho ăn khi vàng dư > {R['bots']['hac']['feed_mult']} × giá; đủ hai con cấp tối đa thì về Lão Hỗn Nguyên ghép Hắc Long. Bot không được báo cả server (trừ khi câu được Long Vương), không vào bảng xếp hạng. Bot cũng ra Biển Long Vương câu cá, nhận việc Ông Lão; Long Vương nổi thì khoảng 1/{R['bots']['fish']['chase_every']} số bot (và mọi bot try hard) ra hồ săn, cơ hội như người chơi. Khoảng 1/{R['bots']['tryhard']['every']} số bot là bot try hard: luôn ép liều, nghỉ ít, leo Tháp và câu cá thường hơn."),
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
        return f"Cửa hàng: {n(v['price'])}" + (f" (từ cấp {v['buy_level']}, đã chuyển sinh thì mua được)" if v.get("buy_level") else "")
    return "—"
def grp(title, ids):
    ids = [i for i in ids if i in IT]
    if not ids:
        return ""
    r = f"<tr class=grp><td colspan=4>{title} ({len(ids)})</td></tr>"
    for i in ids:
        v = IT[i]
        use = v.get("desc") or (f"hồi {n(v['heal'])} máu" if v.get("heal") else f"hồi {n(v['mana'])} MP" if v.get("mana") else "")
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
# bộ tên thay cho tên MU (DECISIONS "Bộ tên thay cho tên MU"): ô tick "Tên mới" trên trang đổi chữ theo bảng này
_alt = json.load(open(os.path.join(os.path.dirname(__file__), "../../priv/static/i18n/names_alt.json"), encoding="utf-8"))
names_alt = json.dumps({k: v[0] for g in _alt["groups"].values() for k, v in g.items()}, ensure_ascii=False).replace("</", "<\\/")
# ---------- Thế giới (DECISIONS "Bản đồ đẹp hơn", "Động Bí Ẩn"): thời tiết, bản đồ mới, Thương Nhân, Động Bí Ẩn ----------
WX = R["weather"]
WXN = {"clear": "☀️ Quang", "rain": "🌧️ Mưa", "storm": "⛈️ Giông", "fog": "🌫️ Sương", "snow": "❄️ Tuyết", "blizzard": "🌨️ Bão tuyết",
       "leaves": "🍂 Lá bay", "dust": "💨 Gió cát", "embers": "🔥 Tàn lửa"}
REGN = {"village": "Làng (và bản đồ nền cỏ)", "lake": "Biển Long Vương", "forest": "Rừng", "swamp": "Đầm lầy", "mountain": "Núi",
        "graveyard": "Nghĩa địa", "camp": "Trại", "lair": "Hang"}
ELN = R["elements"]["names"]
ELI = R["elements"]["icons"]
wx_bonus = "".join(f"<tr><td>{WXN.get(k, k)}</td><td>{ELI.get(v['element'], '')} {E(ELN.get(v['element'], v['element']))}</td><td class=n>+{pct(v['pct'])}</td></tr>"
                   for k, v in WX["bonus"].items())
def _wx_region(opts):
    tot = sum(w for _, w in opts)
    return ", ".join(f"{WXN.get(k, k)} {pct(w / tot)}" for k, w in opts)
wx_regions = "".join(f"<tr><td>{E(REGN.get(r, r))}</td><td>{_wx_region(o)}</td></tr>" for r, o in WX["regions"].items())
vn_maps = [m for m in LIB["maps"] if m["id"].startswith("vn_")]
vn_rows = "".join(
    f"<tr><td><b>{E(m['name'])}</b></td><td class=n>{(str(m['min']) + '–' + str(m['max'])) if m['monsters'] else ('cần cấp ' + str(m['min']) if m['min'] else '—')}</td>"
    f"<td>{E(', '.join(MAPN.get(t, t) for t in m['to'] if t in MAPN))}</td><td>{E(', '.join(MON[k]['name'] for k in m['monsters'] if k in MON)) or 'không có quái'}</td></tr>"
    for m in sorted(vn_maps, key=lambda x: x["min"] or 0))
TRD = R["trader"]
trader_rows = "".join(f"<tr><td>{E(IT.get(o['item'], {}).get('name', o['item']))}{' ×' + str(o['n']) if o['n'] > 1 else ''}</td><td class=n>{n(o['price'])}</td><td class=n>{o['limit']}</td></tr>" for o in TRD["offers"])
SEC = R["secret"]
_side = json.load(open(os.path.join(os.path.dirname(__file__), "../../priv/game_data/side.json"), encoding="utf-8"))["SIDE_MONSTERS"]
_boss = next((m for m in _side if m["id"] == SEC["boss"]), {"name": SEC["boss"], "level": "?"})
secret_li = "".join(f"<li>{x}</li>" for x in [
    f"Cổng: <b>Khe Đá Phát Sáng</b> sau bức tường Đền Cổ Trên Núi. Không dịch chuyển tới được, không có trong Thư viện / Chọn map.",
    f"Chỉ mở ban đêm (20–5 giờ), khoảng <b>{pct(SEC['open_chance'])}</b> số đêm (hỏi Lão Từ Giữ Đền). Cần cấp <b>38</b>. Quản trị mở / đóng được.",
    f"Người đầu tiên vào mỗi đêm được báo cả server và khắc tên lên Bia Động Bí Ẩn.",
    f"Trùm đêm <b>{E(_boss['name'])}</b> (cấp {_boss['level']}): thức giấc một lần mỗi đêm mở, lúc ngẫu nhiên {SEC['boss_from_h']}–{SEC['boss_to_h']} giờ, báo cả server. Hạ được: chắc chắn 1 ngọc, thêm "
    + ", ".join(f"{n} {E(IT.get(k, {}).get('name', k))}" for k, n in SEC["boss_items"].items()) + ", tên lên Bia.",
    f"Quái Tinh Anh (viền tím): {pct(SEC['elite_chance'])} quái trong động, chỉ số ×{n(SEC['elite_mult'])}, vàng / kinh nghiệm ×{n(SEC['elite_reward'])}, tỉ lệ rơi ngọc ×{n(SEC['elite_jewel_mult'])}.",
    f"{SEC['warn_min']} phút trước 5 giờ sáng đá bắt đầu rơi; 5 giờ động sụp, ai còn trong động bị đưa ra Đền Cổ (không mất gì).",
    f"Thành tựu: <b>Kẻ Đi Đêm</b> (vào động {SEC['night_walker']} đêm khác nhau), <b>Diệt Thạch Long</b> (hạ trùm đêm).",
])
# ---------- Kỹ năng quái theo hệ, kháng hệ (DECISIONS "Quái dùng kỹ năng theo hệ") ----------
MS = R["monster_skills"]
EFN = {"burn": "bỏng", "poison": "độc", "weaken": "suy yếu", "stun": "choáng"}
def _ms_desc(k):
    out = []
    if k.get("mult"):
        out.append(f"× {n(k['mult'])} công" + (f" ({k['hits']} đòn)" if k.get("hits") else ""))
    e = k.get("effect")
    if e:
        if e["id"] == "stun":
            out.append(f"{pct(e.get('chance', 1))} choáng 1 lượt")
        elif e["id"] == "weaken":
            out.append(f"suy yếu −{pct(e['power'])} công {e['turns']} lượt")
        else:
            out.append(f"{EFN.get(e['id'], e['id'])} {e['turns']} lượt ({pct(e['power'])} công quái mỗi lượt)")
    if k.get("drain"):
        out.append(f"hồi {pct(k['drain'])} sát thương gây ra")
    if k.get("heal"):
        out.append(f"hồi {pct(k['heal'])} máu tối đa")
    if k.get("self"):
        sf = k["self"]
        out.append(("giảm " if sf["id"] == "stone" else "né thêm ") + pct(sf["power"]) + (" sát thương nhận" if sf["id"] == "stone" else " đòn thường") + f" {sf['turns']} lượt")
    return ", ".join(out)
ms_rows = "".join(
    f"<tr><td>{ELI.get(el, '')} {E(ELN.get(el, el))}</td>" + "".join(f"<td><b>{E(k['name'])}</b><br><span class=small>{_ms_desc(k)}</span></td>" for k in ks) + "</tr>"
    for el, ks in MS["by_element"].items())
TIERN = {"normal": f"Quái thường (cấp {MS['min_level']}+)", "elite": "Tinh Anh, Bóng Đêm, quái vàng", "boss": "Trùm (giữ chiêu đặc biệt cũ)", "lord": "Chúa tể vùng chuyển sinh"}
ms_tiers = "".join(f"<tr><td>{TIERN[t]}</td><td class=n>{MS['tiers'][t]['count']}</td><td class=n>{pct(MS['tiers'][t]['chance'])}</td></tr>" for t in ("normal", "elite", "boss", "lord") if t in MS["tiers"])
LS = MS["lord_special"]
lord_li = ", ".join(f"{ELI.get(el, '')} {E(nm)}" for el, nm in LS["names"].items())
RS = MS["resist"]
res_rows = "".join(f"<tr><td>{E(IT[i]['name'])}</td><td>{ELI.get(el, '')} {E(ELN.get(el, el))}</td></tr>" for i, el in RS["items"].items() if i in IT)
MSKILL_HTML = f"""<h3>Quái dùng kỹ năng theo hệ</h3>
  <p>Quái dùng kỹ năng theo nguyên tố của mình (đánh quái; đồ sát, đấu trường không áp). Kỹ năng luôn trúng, hồi chiêu {MS['cooldown']} lượt; thời tiết cùng hệ cộng như kỹ năng người. Quái dưới cấp {MS['min_level']} chỉ đánh thường.</p>
  <div class="scroll"><table><thead><tr><th>Hệ</th><th>Kỹ năng 1</th><th>Kỹ năng 2</th></tr></thead><tbody>{ms_rows}</tbody></table></div>
  <div class="grid2"><div class="scroll"><table><thead><tr><th>Loại quái</th><th>Số kỹ năng</th><th>Tỉ lệ dùng / lượt</th></tr></thead><tbody>{ms_tiers}</tbody></table></div>
  <div><p class="note">{f"Chúa tể vùng chuyển sinh có thêm chiêu riêng mỗi {LS['every']} lượt (× {n(LS['mult'])} công): {lord_li}." if LS['every'] > 0 else "Chúa tể vùng chuyển sinh dùng 2 kỹ năng của hệ (tỉ lệ thấp hơn quái thường vì chỉ số chúa tể vốn rất cao), không thêm chiêu riêng."} Trùm vùng giữ chiêu đặc biệt cũ.</p></div></div>
  <h3>Kháng hệ (nhẫn, dây chuyền kiểu MU)</h3>
  <p>Mỗi món đang mặc (có tác dụng) kháng {pct(RS['base'])} + {pct(RS['per_up'])} mỗi cấp ép (+11: {pct(RS['base'] + 11 * RS['per_up'])}); nhiều món cùng hệ cộng dồn, tối đa {pct(RS['max'])}. Kháng giảm sát thương kỹ năng quái cùng hệ đúng tỉ lệ đó và cũng là tỉ lệ kháng hiệu ứng xấu (bỏng, độc, suy yếu, choáng) của kỹ năng đó. Như MU: Độc → Bóng Tối, Nước → Ánh Sáng; Nhẫn Phép không có kháng.</p>
  <div class="scroll"><table><thead><tr><th>Món</th><th>Kháng hệ</th></tr></thead><tbody>{res_rows}</tbody></table></div>
"""
WORLD_HTML = f"""<h3>Thời tiết</h3>
  <p>Đổi mỗi {WX['slot_min']} phút (giờ Việt Nam), cả server thấy như nhau; biểu tượng cạnh tên bản đồ. Đánh quái (không tính đánh người): kỹ năng cùng hệ với thời tiết gây thêm sát thương.</p>
  <div class="grid2"><div class="scroll"><table><thead><tr><th>Thời tiết</th><th>Hệ được cộng</th><th>Cộng</th></tr></thead><tbody>{wx_bonus}</tbody></table></div>
  <div class="scroll"><table><thead><tr><th>Vùng</th><th>Thời tiết (tỉ lệ mỗi giờ)</th></tr></thead><tbody>{wx_regions}</tbody></table></div></div>
  <h3>Bản đồ mang chất Việt</h3>
  <div class="scroll"><table><thead><tr><th>Bản đồ</th><th>Cấp quái</th><th>Nối với</th><th>Quái</th></tr></thead><tbody>{vn_rows}</tbody></table></div>
  <p class="note">Ruộng Bậc Thang và Đồng Bằng Sông Nước là bản đồ lớn 50×35. Làng Chài, Chợ Nổi, Đồng Bằng câu cá được (bảng cá vùng sâu).</p>
  <h3>Thương Nhân Phương Xa (Chợ Nổi)</h3>
  <p>Mỗi ngày bày {TRD['show']} trong {len(TRD['offers'])} món (đổi theo ngày), mỗi món mua tối đa vài lần mỗi ngày.</p>
  <div class="scroll"><table><thead><tr><th>Món</th><th>Giá (vàng)</th><th>Lần / ngày</th></tr></thead><tbody>{trader_rows}</tbody></table></div>
  <h3>Động Bí Ẩn</h3><ul>{secret_li}</ul>
  {MSKILL_HTML}"""
page = open(os.path.join(os.path.dirname(__file__), "tpl.html"), encoding="utf-8").read()
for k, v in dict(OVERVIEW=overview, TABS=tabs, PANES=panes, TIERS=trows, JEW=jrows, WINGS=wrows, WINGUP=wuprows, UPG=erows, EXC_W=exl("weapon"),
                 EXC_A=exl("armor"), ANC=anc_li, OPT=opt_li, LOOT=lrows, SLOTS=", ".join(slot_txt), STABS=stabs, SPANES=spanes,
                 CYCLE=cycle, BYLV=bylv, REALMS=rrows, LADDER=LADDER_HTML, OTHER=other, STATROWS=stat_rows, MODEROWS=mode_rows, TAKENROWS=taken_rows, TAKENARENA=taken_arena, EVMON=evmon, MONSTER=monster_line, RULELI=rule_li, GAPS=gap_note, EVROWS=ev_rows, FEST=fest, FESTSHOP=fest_shop, MAPROWS=map_rows, BOSSROWS=boss_rows, BOSSNOTE=boss_note, TOWERROWS=tower_rows, PKLI=pk_li, PKQUICK=PK_QUICK, TOOLS=TOOLS_HTML, EVVIZ=EVVIZ_HTML, PKEV=PKEV_HTML, SKY=SKY_HTML, PETROWS=pet_rows, PETRULE=pet_rule, PETTAME=pet_tame, TWHARD=str(TW['harder_from']), TWPER=pct(TW['harder_per_floor']), TWBOSS=str(TW['boss_every']), TWELITE=n(TW['elite_mult']), TWOFF=str(TW['level_offset']), TRAVEL=f"{R['travel']['base']} + {R['travel']['per_level']} × cấp quái thấp nhất", CLASSROWS=class_rows, EVSCALE=f"<b>Sự kiện đánh chung theo phòng (kiểu MU)</b>: Quảng Trường Quỷ, Lâu Đài Máu, Hỗn Chiến Thành chia phòng theo số lần chuyển sinh ({', '.join(f'{a}–{b}' if b < R['character']['max_rebirths'] else f'{a}+' for a, b in R['event_rooms']['bands'])}); cùng phòng thì chung bản đồ, chung quái, chung máu quái. Kalima theo tổ đội. Quái mạnh theo mốc k của <b>phòng</b> (mốc cao nhất của khoảng; Kalima: người chuyển sinh nhiều nhất trong tổ đội; Vương Miện Công Thành Chiến cố định k = {R['event_scale']['crown_rebirths']}): máu và thủ × (1 + {n(R['event_scale']['hp_per_rebirth'])} × k), công × (1 + {n(R['event_scale']['atk_per_rebirth'])} × k), kinh nghiệm và vàng × (1 + {n(R['event_scale']['reward_per_rebirth'])} × k); k tối đa {R['character']['max_rebirths']}. Người hạ quái được điểm, người cùng đánh được vàng / kinh nghiệm theo phần sát thương; Lâu Đài: người gây nhiều sát thương nhất lên trùm nhận Lông Vũ. Quái vàng, trùm thế giới và tháp không áp.", SMITH=smith_note, CHAOSROWS=chaos_rows, LINESROWS=lines_rows, LINESEX=lines_example, JEWELSRC=jewel_src, POTLV=pct(R['shop']['potion_price_per_level']), RLOOT=pct(rl['loot_per_realm']), RLOOTMAX=pct(rl['loot_max']), LUCKREAL=pct(luck_real), COSTMIN=n(UPR['cost_min_price']), COSTPCT=pct(UPR['cost_pct']),
                 SB=f"+{pct(sb['def_pct'])} thủ, +{pct(sb['atk_pct'])} công, +{sb['hp_per_tier']} máu × bậc bộ",
                 UPPCT=pct(R['upgrade']['bonus_pct']), ANNOUNCE=str(up['announce_from']), DOUBLE=str(up['double_from']),
                 LUCKUP=luck_up, LUCKMAX=pct(ls['luck_max_rate']), LUCKCRIT=pct(ls['luck_crit']), SKILLDMG=pct(ls['skill_dmg']),
                 LIFE=f"{pct(life['per_line_pct'])} công / thủ gốc của món (ít nhất +{life['per_line']}) mỗi dòng, tối đa {life['max_lines']} dòng, {pct(life['rate'])}",
                 EXCLINES=", ".join(f"{a} dòng {pct(b/sum(w for _, w in ex['lines']))}" for a, b in ex["lines"]),
                 EXCPRICE=n(ex['price_mult']), DMGRED=pct(ex['max_dmg_red']), REFL=pct(ex['max_reflect']),
                 ANCDEF=pct(anc['piece_def_pct']), ANCPRICE=n(anc['price_mult']), PERLINE=f"{pct(life['per_line_pct'])} công / thủ gốc của món (ít nhất +{life['per_line']})",
                 STRONG=pct(EL['strong']), WEAK=pct(EL['weak']), LOADOUT=str(R['tower_skills']['loadout']), MASTERY=mastery_note(),
                 RMIN=str(rl['min_level']), REBIRTH=f"Tối đa {R['character']['rebirth_per_day']} lần chuyển sinh mỗi ngày. Trùm vùng và trùm đêm Động Bí Ẩn mạnh lên theo số lần chuyển sinh của người đánh (như quái sự kiện). Chuyển sinh lần n: +{R['character']['rebirth_points']} × n điểm tiềm năng, máu tối đa × (1 + {pct(R['character']['rebirth_hp_pct'])} × n) (quá {R['character']['max_rebirths']} lần mỗi lần thêm {pct(R['character']['endless_hp_pct'])}), kinh nghiệm lên cấp × (1 + {pct(R['character']['rebirth_xp_pct'])} × n); từ lần {R['character']['rebirth_lord_from'] + 1}, muốn chuyển sinh lần k + 1 phải từng hạ chúa tể vùng k. Không giới hạn: quá {R['character']['max_rebirths']} lần mỗi lần chỉ +{R['character']['endless_points']} điểm, kinh nghiệm như lần {R['character']['max_rebirths']}, phải hạ lại chúa tể vùng {R['character']['max_rebirths']} (tổng n − {R['character']['max_rebirths'] - 1} lần).", RSTAT=str(rl['stat_level']), RMULT=n(rl['mult_per_realm']), RXP=n(rl['xp_mult_per_realm']), RBOSS=n(rl['boss_mult']), RATK=n(rl['atk_mult_per_realm']), RLATK=n(rl['lord_atk_mult']), RMAPS=str(rl['maps_per_realm']), RSTEP=n(rl['depth_step']),
                 SELL=pct(R['shop']['sell_ratio']), NAMESALT=names_alt, WORLD=WORLD_HTML, NAMESN=str(len(json.loads(names_alt)))).items():
    page = page.replace("{{" + k + "}}", v)
assert "{{" not in page, page[page.index("{{"):page.index("{{") + 40]
open(OUT, "w", encoding="utf-8").write(page)
json.dump(sorted(USED), open(OUT + ".files.json", "w"))
print(len(page), "bytes,", len(USED), "hình")

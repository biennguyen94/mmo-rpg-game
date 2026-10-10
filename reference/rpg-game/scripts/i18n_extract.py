#!/usr/bin/env python3
"""Trích mọi câu tiếng Việt (giao diện, dữ liệu game, tin server) thành mẫu khóa cho bộ dịch (priv/static/js/i18n.js).

Khóa = câu đã thay TÊN (đồ, quái, NPC, bản đồ, kỹ năng, lớp…) và SỐ / chỗ nội suy bằng {0}, {1}… theo thứ tự xuất hiện —
đúng cách i18n.js chuẩn hóa chữ lúc chạy. Kết quả: priv/static/i18n/source.json = {"names": [...], "t": [...]}.
Chạy lại sau khi thêm chữ mới; bản dịch ở priv/static/i18n/en.json (thiếu thì hiện tiếng Việt).
"""
import glob, json, re, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VI = re.compile(r'[À-ÖØ-öø-ỹĐđ]')
names = set()

def walk_data(o, key=None):
    if isinstance(o, dict):
        for k, v in o.items():
            if k in ('name', 'title') and isinstance(v, str) and VI.search(v) and len(v) <= 40:
                names.add(v.strip())
            walk_data(v, k)
    elif isinstance(o, list):
        for v in o: walk_data(v, key)

texts = set()
def walk_texts(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k in ('banned_words', 'banned_parts'): continue
            walk_texts(v)
    elif isinstance(o, list):
        for v in o: walk_texts(v)
    elif isinstance(o, str) and VI.search(o):
        texts.add(o)

for f in glob.glob(ROOT + '/priv/game_data/*.json') + glob.glob(ROOT + '/priv/maps/*.json'):
    # bảng chọn đồ Phase 15b: tên bộ giáp ngắn ("Da", "Rồng"…) không phải tên riêng; tên đầy đủ ở items_mu.json
    if f.endswith('item_pick.json'): continue
    d = json.load(open(f))
    walk_data(d); walk_texts(d)

INTERP = '\u0001'
# JS: không ghép dấu nháy (template lồng nhau làm lệch); thay vào đó gom dần các nhóm {…} trong cùng ra ngoài:
# `${…}` → dấu nội suy, nhóm khác → chỗ ngắt; mỗi lần gom thì nhặt các đoạn chữ tiếng Việt nằm giữa các dấu phân cách.
SEP = '\u0003'
DELIM = re.compile(r"[`'\"<>\n" + SEP + r"]|\\n")
def harvest(s, out):
    for part in DELIM.split(s):
        if VI.search(part): out.append(part)
def js_strings(src):
    out = []
    inner = re.compile(r'(\$?)\{([^{}]*)\}')
    while True:
        m = inner.search(src)
        if not m: break
        def sub(m):
            harvest(m.group(2), out)
            return INTERP if m.group(1) else SEP
        src = inner.sub(sub, src)
    harvest(src, out)
    # bỏ thẻ HTML còn sót trong đoạn
    return [re.sub(r'<[^>]*>', SEP, p) for p in out]

def ex_strings(src):
    out = []
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', src):
        s = m.group(1)
        if VI.search(s): out.append(re.sub(r'#\{[^}]*\}', INTERP, s))
    return out

def strip_js(src):
    # bỏ dòng chú thích // và khối /* */
    src = re.sub(r'/\*[\s\S]*?\*/', '', src)
    return '\n'.join(l for l in src.split('\n') if not l.lstrip().startswith('//'))

def strip_ex(src):
    # bỏ @doc / @moduledoc (heredoc) và dòng chú thích #
    src = re.sub(r'"""[\s\S]*?"""', '', src)
    return '\n'.join(re.sub(r'(^|\s)#\s.*$', '', l) if not l.lstrip().startswith('#') else '' for l in src.split('\n'))

for f in glob.glob(ROOT + '/priv/static/js/*.js'):
    for s in js_strings(strip_js(open(f).read())): texts.add(s)
for f in glob.glob(ROOT + '/lib/**/*.ex', recursive=True):
    if '/mix/' in f: continue
    for s in ex_strings(strip_ex(open(f).read())): texts.add(s)

name_list = sorted(names, key=len, reverse=True)
name_re = '|'.join(re.escape(n) for n in name_list)
# {a} {b} {n}: chỗ trống của câu bình luận Tiến Lên (commentary.ex), đánh số như tên / số
TOK = re.compile('(' + (name_re + '|' if name_re else '') + r'\d+(?:[.,]\d+)*|\{[abn]\}|' + INTERP + ')')

def key(s):
    s = re.sub(r'\s+', ' ', s.replace('\\n', ' ')).strip()
    i = 0
    def sub(m):
        nonlocal i
        r = '{%d}' % i; i += 1; return r
    return TOK.sub(sub, s)

keys = set()
for t in texts:
    for line in re.split(r'\n|' + SEP, t):
        k = key(line)
        k = k.strip(' ·,:;')
        if VI.search(k) and len(k) <= 400 and not re.search(r'`|%\{|\)\.join|=>|\$\{', k):
            keys.add(k)
json.dump({'names': name_list, 't': sorted(keys)}, open(ROOT + '/priv/static/i18n/source.json', 'w'), ensure_ascii=False, indent=0)
print(len(name_list), 'names,', len(keys), 'templates,', sum(len(k) for k in keys), 'chars')

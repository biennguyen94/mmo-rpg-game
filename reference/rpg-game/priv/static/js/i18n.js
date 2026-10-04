// Hai ngôn ngữ (Phase 10, U1): Tiếng Việt (gốc) / English.
//
// Không sửa từng câu trong code: mọi chữ hiện ra (giao diện, tên đồ / quái / NPC, tin từ server, nhật ký trận, chữ
// vẽ trên bản đồ) đi qua `tr()`. Câu được chuẩn hóa thành mẫu: TÊN (từ `names`) và SỐ thay bằng {0}, {1}… theo thứ tự,
// tra trong `t`, rồi điền lại (tên dịch theo `names`). Từ điển ở `/i18n/en.json`, sinh khóa bằng
// `scripts/i18n_extract.py`. Câu chưa có bản dịch thì giữ tiếng Việt (chỉ đổi những tên đã biết).
//
// Một MutationObserver dịch chữ mới chèn vào trang; tin chat của người chơi không dịch (`.chat-line` không phải tin
// hệ thống), ô nhập không dịch. Chọn ngôn ngữ trong Cài đặt (lưu ở trình duyệt), đổi thì tải lại trang.
(function (root) {
  const KEY = 'hl-lang';
  let lang = 'vi';
  try { lang = localStorage.getItem(KEY) || 'vi'; } catch (e) { /* bộ nhớ trình duyệt bị chặn: tiếng Việt */ }
  const VI = /[À-ỹĐđ]/;
  let dict = { names: {}, t: {} }, tokRe = null, nameOnly = null, loose = {};
  const cache = new Map();
  const reEsc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

  function load(d) {
    dict = { names: d.names || {}, t: d.t || {} };
    const names = Object.keys(dict.names).sort((a, b) => b.length - a.length).map(reEsc);
    tokRe = new RegExp('(' + names.concat(['\\d+(?:[.,]\\d+)*']).join('|') + ')', 'g');
    nameOnly = names.length ? new RegExp('(' + names.join('|') + ')', 'g') : null;
    // mẫu dự phòng: {n} nhận chữ bất kỳ (tên người chơi, bang…), xếp theo từ đầu tiên để tra nhanh
    loose = {};
    for (const [k, v] of Object.entries(dict.t)) {
      if (!/\{\d+\}/.test(k)) continue;
      const first = k.split(/[\s{]/)[0] || '';
      const re = new RegExp('^' + k.split(/\{(\d+)\}/).map((p, i) => (i % 2 ? '(?<p' + p + '>.+?)' : reEsc(p))).join('') + '$');
      (loose[first] = loose[first] || []).push([re, v]);
    }
  }

  // dịch phần lõi (đã bỏ khoảng trắng / dấu ngăn ở hai đầu)
  function core(s) {
    const norm = s.replace(/\s+/g, ' ');
    if (dict.t[norm]) return dict.t[norm];
    if (dict.names[norm]) return dict.names[norm];
    const vals = [];
    const key = norm.replace(tokRe, (x) => { vals.push(x); return '{' + (vals.length - 1) + '}'; });
    const tpl = dict.t[key];
    if (tpl) return tpl.replace(/\{(\d+)\}/g, (m, i) => (vals[i] == null ? m : dict.names[vals[i]] || vals[i]));
    const first = norm.split(/[\s{]/)[0] || '';
    for (const [re, v] of (loose[first] || []).concat(first ? loose[''] || [] : [])) {
      const m = norm.match(re);
      if (m) return v.replace(/\{(\d+)\}/g, (x, i) => { const g = m.groups['p' + i]; return g == null ? x : tr(g); });
    }
    // chưa có mẫu: ít nhất đổi các tên đã biết
    return nameOnly ? norm.replace(nameOnly, (x) => dict.names[x] || x) : norm;
  }

  function tr(s) {
    if (lang === 'vi' || !s || !tokRe || !VI.test(s)) return s;
    if (cache.has(s)) return cache.get(s);
    const m = s.match(/^([\s·,:;]*)([\s\S]*?)([\s·,:;]*)$/);
    const out = m[1] + core(m[2]) + m[3];
    if (cache.size > 5000) cache.clear();
    cache.set(s, out);
    return out;
  }

  // ---------- Dịch trang ----------
  const SKIP = 'script,style,textarea,input,select,.chat-line:not(.system),[data-notr]';
  const ATTRS = ['placeholder', 'title', 'aria-label'];
  const skip = (el) => !el || (el.closest && el.closest(SKIP));
  function text(n) {
    const v = n.nodeValue;
    if (!v || n.__hl === v || skip(n.parentElement)) return;
    const o = tr(v);
    n.__hl = o;
    if (o !== v) n.nodeValue = o;
  }
  function attrs(el) {
    for (const a of ATTRS) {
      const v = el.getAttribute && el.getAttribute(a);
      if (v && VI.test(v)) { const o = tr(v); if (o !== v) el.setAttribute(a, o); }
    }
  }
  function walk(node) {
    if (node.nodeType === 3) return text(node);
    if (node.nodeType !== 1 || skip(node)) return;
    attrs(node);
    node.querySelectorAll('[placeholder],[title],[aria-label]').forEach((el) => { if (!skip(el)) attrs(el); });
    const w = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
    for (let t = w.nextNode(); t; t = w.nextNode()) text(t);
  }
  function start() {
    if (lang === 'vi') return;
    document.documentElement.lang = 'en';
    walk(document.body);
    new MutationObserver((ms) => {
      for (const m of ms) {
        if (m.type === 'characterData') text(m.target);
        else if (m.type === 'attributes') attrs(m.target);
        else m.addedNodes.forEach(walk);
      }
    }).observe(document.body, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ATTRS });
    // hộp hỏi lại của trình duyệt
    const c = root.confirm, p = root.prompt;
    root.confirm = (msg) => c.call(root, tr(msg));
    root.prompt = (msg, d) => p.call(root, tr(msg), d);
  }

  // Tiếng Anh: nạp từ điển đồng bộ trước khi giao diện vẽ (một lần, ~100 KB, được trình duyệt lưu đệm).
  if (lang === 'en' && typeof XMLHttpRequest !== 'undefined') {
    try {
      const x = new XMLHttpRequest();
      x.open('GET', 'i18n/en.json', false);
      x.send();
      if (x.status === 200) load(JSON.parse(x.responseText));
    } catch (e) { lang = 'vi'; }
  }

  const I18N = {
    get lang() { return lang; },
    tr,
    load,
    set(l) { try { localStorage.setItem(KEY, l); } catch (e) { /* không lưu được: chỉ đổi lần này */ } location.reload(); },
  };
  root.I18N = I18N;
  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = { tr: (s) => { lang = 'en'; return tr(s); }, load };
})(typeof window !== 'undefined' ? window : globalThis);

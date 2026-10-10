/* Tiến Lên Miền Nam (Phase 17): sảnh, bàn bài, xem trận, xem lại ván.
 * Viết lại bằng JS thuần từ các LiveView của repo Tien-Len-Mien-Nam (table_live, lobby_live,
 * spectate_live, replay_live). Client không có luật: nút Đánh / Bỏ lượt / Chặt hiện theo
 * kết quả thử của server (lệnh "check"); bài người khác không bao giờ tới đây.
 * Mở bằng TL.open() (NPC Chủ Sòng ở Làng hoặc Menu → 🃏). */
(function () {
  'use strict';

  const RANKS = { 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, 10: 10, J: 11, Q: 12, K: 13, A: 14, 2: 15 };
  const SUITS = { S: 0, C: 1, D: 2, H: 3 };
  const SUIT_SYM = { S: '♠', C: '♣', D: '♦', H: '♥' };
  const PLACES = ['', 'Nhất', 'Nhì', 'Ba', 'Bét'];
  const MEDALS = ['', '🥇', '🥈', '🥉', ''];

  const st = {
    open: false, screen: 'lobby', meta: null, rooms: [], roomId: null, watching: null,
    view: null, sel: new Set(), sort: 'rank', checks: null, hintI: 0, deadline: null,
    chat: [], chatOpen: false, ticker: null, reactions: {}, marks: {}, speech: {}, puffs: {}, runaways: {},
    throwMenu: null, msg: null, games: [], replay: null, frame: 0, playing: null, busy: false,
  };
  let root = null, checkTimer = null;

  // ---------- tiện ích ----------
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fmt = (n) => (n == null ? '—' : Number(n).toLocaleString('vi-VN'));
  const signed = (n) => (n > 0 ? '+' + fmt(n) : fmt(n));
  const now = () => Date.now();
  const parts = (code) => ({ rank: RANKS[code.slice(0, -1)], suit: SUITS[code.slice(-1)] });
  const cardKey = (code) => { const p = parts(code); return (p.rank - 3) * 4 + p.suit; };
  const cardLabel = (code) => code.slice(0, -1) + SUIT_SYM[code.slice(-1)];
  const cardSrc = (code) => `assets/cards/${code.replace(/^10/, 'T')}.svg`;
  const cardImg = (code, cls) => `<img class="tl-card ${cls || ''}" src="${cardSrc(code)}" alt="${cardLabel(code)}" title="${cardLabel(code)}" draggable="false">`;
  const typeName = (t) => (st.meta && st.meta.types[t]) || t;
  const instName = (t) => (st.meta && st.meta.instants[t]) || t;
  const player = (v, seat) => v && v.players.find((p) => p.seat === seat);
  const nameOf = (seat) => { const p = player(st.view, seat); return p ? p.name : `Ghế ${seat + 1}`; };
  const sound = (n) => { try { window.Sound && window.Sound.play(n); } catch (e) { /* bỏ qua */ } };

  function say(text, bad) { st.msg = { text, bad, until: now() + 3500 }; render(); }
  async function call(op, payload) {
    try { return await window.Net.tl(op, payload); } catch (e) { say((e && e.msg) || 'Có lỗi xảy ra', true); sound('error'); return null; }
  }

  // ---------- mở / đóng ----------
  function ensureRoot() {
    if (root) return;
    root = document.createElement('div');
    root.id = 'tl-root';
    root.className = 'tl-overlay';
    root.hidden = true;
    document.body.appendChild(root);
    root.addEventListener('click', onClick);
    root.addEventListener('submit', onSubmit);
  }

  async function open() {
    ensureRoot();
    st.open = true;
    root.hidden = false;
    document.body.classList.add('tl-on');
    await loadLobby(true);
  }

  function close() {
    st.open = false;
    if (root) root.hidden = true;
    document.body.classList.remove('tl-on');
  }

  // `resume`: đang ngồi bàn thì vào thẳng bàn (lúc mở); bấm "Sảnh" thì ở lại sảnh
  async function loadLobby(resume) {
    const r = await call('lobby');
    if (!r) { render(); return; }
    st.meta = r;
    st.rooms = r.rooms || [];
    st.roomId = r.room || null;
    if (r.room && resume) {
      const v = await call('view');
      if (v) { setView(v.view, []); st.screen = 'table'; await loadChat(); } else { st.roomId = null; st.screen = 'lobby'; }
    } else if (st.screen === 'table' && !r.room) st.screen = 'lobby';
    render();
  }

  async function loadChat() {
    const r = await call('chat_history');
    st.chat = (r && r.chat) || [];
  }

  // ---------- trạng thái bàn ----------
  function setView(view, events) {
    const was = st.view;
    st.view = view;
    if (!view) return;
    const g = view.game;
    const hand = (g && g.hand) || [];
    st.sel = new Set([...st.sel].filter((c) => hand.includes(c)));
    st.deadline = view.turn_ms_left != null ? now() + view.turn_ms_left : null;
    st.hintI = 0;
    // RC1: người rời bàn giữa ván để lại chiếc dép
    const ev = events || [];
    ev.filter((e) => e[0] === 'removed').forEach((e) => {
      if (ev.some((x) => x[0] === 'left' && x[1] === e[1])) st.runaways[e[1]] = now() + 4000;
    });
    if (ev.some((e) => e[0] === 'game_started')) sound('encounter');
    if (ev.some((e) => e[0] === 'game_over') && view.me != null && g) {
      const first = (g.ranking[0] || []).includes(view.me);
      sound(first ? 'win' : 'lose');
    }
    if (was && g && g.current === view.me && was.game && was.game.current !== view.me && view.status === 'playing') sound('notice');
    scheduleCheck();
  }

  function scheduleCheck() {
    clearTimeout(checkTimer);
    const v = st.view;
    if (!v || v.status !== 'playing' || v.me == null || st.watching) { st.checks = null; return; }
    checkTimer = setTimeout(async () => {
      const r = await window.Net.tl('check', { cards: [...st.sel] }).catch(() => null);
      st.checks = r;
      renderActions();
    }, 60);
  }

  // ---------- sự kiện từ server ----------
  function onTl(m) {
    if (!st.open && !st.roomId) return;
    if (m.id !== st.roomId && m.id !== st.watching) return;
    if (!m.view) {
      if ((m.events || []).some((e) => e[0] === 'closed')) say('Phòng đã đóng.', true);
      st.roomId = null; st.view = null; st.screen = 'lobby'; loadLobby(); return;
    }
    setView(m.view, m.events);
    if (st.open) render();
  }

  function onChat(msg) {
    if (msg.deleted) { st.chat = st.chat.filter((c) => c.id !== msg.deleted); render(); return; }
    st.chat = st.chat.concat([msg]).slice(-50);
    if (msg.system) st.ticker = { text: msg.text, until: now() + 5000 };
    if (msg.bot && msg.seat != null) st.speech[msg.seat] = { text: msg.text, until: now() + 3500 };
    if (st.open) render();
  }

  function onFx(f) {
    const t = now();
    if (f.kind === 'reaction') st.reactions[f.seat] = { emoji: f.emoji, until: t + 3000 };
    if (f.kind === 'throw') {
      const item = (st.meta && st.meta.throws.find((i) => i.id === f.item)) || { emoji: '❓', mark: '' };
      st.marks[f.to] = { text: item.emoji + item.mark, until: t + 3700 };
      sound('hit');
    }
    if (f.kind === 'blow') st.puffs[f.seat] = t + 2000;
    if (f.kind === 'effects') {
      (f.effects || []).forEach((k) => sound({ chop: 'crit', pig: 'coin', confetti: 'achieve' }[k] || 'notice'));
      if ((f.effects || []).includes('chop')) shake();
    }
    if (st.open) render();
  }

  function shake() {
    const t = root && root.querySelector('.tl-table');
    if (t) { t.classList.remove('shake'); void t.offsetWidth; t.classList.add('shake'); }
  }

  // ---------- thao tác ----------
  async function act(op, payload) {
    if (st.busy) return;
    st.busy = true;
    const r = await call(op, payload);
    st.busy = false;
    if (r && ['play', 'chop', 'pass'].includes(op)) { st.sel.clear(); }
    if (r) { const v = await call('view'); if (v) setView(v.view, []); }
    render();
    return r;
  }

  async function sit(id) {
    const r = await call('join', { id });
    if (!r) return;
    st.roomId = r.id; st.watching = null; st.screen = 'table'; st.chat = [];
    setView(r.view, []);
    await loadChat();
    render();
  }

  async function create(stake, priv) {
    const r = await call('create', { stake, private: priv });
    if (!r) return;
    st.roomId = r.id; st.watching = null; st.screen = 'table'; st.chat = [];
    setView(r.view, []);
    render();
  }

  async function watch(id) {
    const r = await call('watch', { id });
    if (!r) return;
    st.watching = id; st.screen = 'watch';
    setView(r.view, []);
    render();
  }

  async function leave() {
    if (st.view && st.view.status === 'playing' && !confirm('Đang trong ván: rời bàn sẽ bị loại khỏi ván này (bị tính Bét). Vẫn rời?')) return;
    await call('leave');
    st.roomId = null; st.view = null; st.chat = []; st.screen = 'lobby';
    await loadLobby();
  }

  async function hint() {
    const r = await call('hints');
    if (!r) return;
    if (!r.hints.length) { say('Không có bài nào đánh được, hãy bỏ lượt', true); return; }
    const i = st.hintI % r.hints.length;
    st.sel = new Set(r.hints[i]);
    st.hintI = i + 1;
    scheduleCheck();
    render();
  }

  async function history() {
    const r = await call('history');
    st.games = (r && r.games) || [];
    st.screen = 'history';
    render();
  }

  async function replay(id) {
    const r = await call('replay', { id });
    if (!r) return;
    st.replay = r; st.frame = 0; st.screen = 'replay';
    render();
  }

  // ---------- chuột / bàn phím ----------
  function onClick(e) {
    const t = e.target.closest('[data-tl]');
    if (!t) return;
    const a = t.dataset.tl, d = t.dataset;
    e.preventDefault();
    switch (a) {
      case 'close': close(); window.dispatchEvent(new Event('tl-closed')); break;
      case 'lobby': st.screen = 'lobby'; if (st.watching) { call('unwatch'); st.watching = null; st.view = null; } loadLobby(); break;
      case 'refresh': loadLobby(); break;
      case 'join': sit(d.id); break;
      case 'watch': watch(d.id); break;
      case 'back-table': loadLobby(true); break;
      case 'leave': leave(); break;
      case 'start': act('start'); break;
      case 'card': {
        const c = d.card;
        if (st.sel.has(c)) st.sel.delete(c); else st.sel.add(c);
        scheduleCheck(); render(); break;
      }
      case 'clear': st.sel.clear(); scheduleCheck(); render(); break;
      case 'play': act('play', { cards: [...st.sel] }); break;
      case 'chop': act('chop', { cards: [...st.sel] }); break;
      case 'pass': act('pass'); break;
      case 'hint': hint(); break;
      case 'sort': st.sort = st.sort === 'rank' ? 'suit' : 'rank'; render(); break;
      case 'add-bot': act('add_bot', { level: d.level }); break;
      case 'remove-bot': act('remove_bot', { seat: +d.seat }); break;
      case 'private': act('private', { private: !(st.view && st.view.private) }); break;
      case 'react': call('react', { emoji: d.emoji }); break;
      case 'seat': if (d.target) { st.throwMenu = st.throwMenu === +d.seat ? null : +d.seat; render(); } break;
      case 'throw': { const to = st.throwMenu; st.throwMenu = null; call('throw', { to, item: d.item }); render(); break; }
      case 'blow': call('blow'); break;
      case 'phrase': call('chat', { text: d.text }); break;
      case 'chat-toggle': st.chatOpen = !st.chatOpen; render(); break;
      case 'history': history(); break;
      case 'replay': replay(+d.id); break;
      case 'frame': {
        const n = st.replay ? st.replay.frames.length - 1 : 0;
        const to = { first: 0, prev: st.frame - 1, next: st.frame + 1, last: n }[d.to];
        st.frame = Math.max(0, Math.min(n, to));
        render(); break;
      }
      case 'autoplay': toggleAutoplay(); break;
      case 'sound': if (window.Sound) window.Sound.toggle(); render(); break;
      default: break;
    }
  }

  function onSubmit(e) {
    const f = e.target;
    if (!f.dataset || !f.dataset.tlForm) return;
    e.preventDefault();
    const v = (name) => (f.elements[name] ? f.elements[name].value : '');
    if (f.dataset.tlForm === 'create') create(Math.floor(+v('stake') || 0), f.elements.private && f.elements.private.checked);
    if (f.dataset.tlForm === 'code') { const id = v('code').trim(); if (id) sit(id); }
    if (f.dataset.tlForm === 'stake') act('stake', { stake: Math.floor(+v('stake') || 0) });
    if (f.dataset.tlForm === 'chat') {
      const text = v('text').trim();
      if (text) call('chat', { text }).then((r) => { if (r) { f.elements.text.value = ''; } });
    }
  }

  function toggleAutoplay() {
    if (st.playing) { clearInterval(st.playing); st.playing = null; render(); return; }
    st.playing = setInterval(() => {
      if (!st.replay || st.screen !== 'replay' || st.frame >= st.replay.frames.length - 1) { clearInterval(st.playing); st.playing = null; render(); return; }
      st.frame += 1; render();
    }, 900);
    render();
  }

  // ---------- vẽ ----------
  function render() {
    if (!root || !st.open) return;
    const scr = st.screen;
    const body = scr === 'table' && st.view ? viewTable(false)
      : scr === 'watch' && st.view ? viewTable(true)
      : scr === 'history' ? viewHistory()
      : scr === 'replay' && st.replay ? viewReplay()
      : viewLobby();
    const m = st.msg && st.msg.until > now() ? `<div class="tl-msg ${st.msg.bad ? 'bad' : ''}" role="status">${esc(st.msg.text)}</div>` : '';
    root.innerHTML = `<div class="tl-wrap">${body}${m}</div>`;
    const log = root.querySelector('.tl-chat-log');
    if (log) log.scrollTop = log.scrollHeight;
  }

  // chỉ vẽ lại hàng nút (sau khi server trả kết quả thử) để không giật cả bàn
  function renderActions() {
    const el = root && root.querySelector('#tl-actions');
    if (el) el.outerHTML = viewActions();
  }

  function head(title, right) {
    return `<div class="tl-head"><button class="btn" data-tl="close">‹ Bản đồ</button><h2 class="grow">${title}</h2>${right || ''}</div>`;
  }

  function viewLobby() {
    const meta = st.meta || {};
    const rooms = st.rooms.map((r) => `<div class="item tl-room">
        <div class="grow"><div class="name">Phòng <span class="tl-code">${esc(r.id)}</span>${r.private ? ' 🔒' : ''}</div>
        <div class="small muted">${esc(r.host_name || '—')} · ${r.players}/${r.max_players} người · ${r.status === 'playing' ? 'đang chơi' : 'đang chờ'} · ${r.stake ? `cược ${fmt(r.stake)} vàng` : 'chơi vui'}</div></div>
        ${r.joinable ? `<button class="btn primary" data-tl="join" data-id="${esc(r.id)}">Vào</button>` : ''}
        <button class="btn" data-tl="watch" data-id="${esc(r.id)}">👀 Xem</button></div>`).join('');
    return `${head('🃏 Tiến Lên Miền Nam', `<button class="btn" data-tl="history">📜 Ván đã chơi</button>`)}
      ${st.roomId ? `<div class="card"><button class="btn primary block" data-tl="back-table">Về bàn đang ngồi (${esc(st.roomId)})</button></div>` : ''}
      <div class="card"><h3>Mở bàn mới</h3>
        <form data-tl-form="create" class="tl-form">
          <label class="small">Mức cược (vàng, 0 = chơi vui)<input type="number" name="stake" min="0" max="${meta.stake_max || 100000}" step="10" value="0" inputmode="numeric"></label>
          <label class="small tl-check"><input type="checkbox" name="private"> Bàn riêng (không hiện ở sảnh)</label>
          <button class="btn primary">Mở bàn</button>
        </form>
        <p class="small muted">Cược S: cần ít nhất 10×S vàng mới được chia bài. Bàn có máy chơi chỉ chơi vui (cược 0).</p>
        <form data-tl-form="code" class="tl-form row"><input name="code" placeholder="Mã phòng" class="grow" autocomplete="off"><button class="btn">Vào bằng mã</button></form>
      </div>
      <div class="card"><div class="row"><h3 class="grow">Các bàn</h3><button class="btn" data-tl="refresh">↻</button></div>
        <div class="list">${rooms || '<p class="small muted">Chưa có bàn nào. Mở một bàn rồi thêm máy chơi để chơi ngay.</p>'}</div></div>
      <div class="card small muted"><h3>Luật chính</h3>
        <p>3 → 2, ♠ &lt; ♣ &lt; ♦ &lt; ♥. Bộ: lẻ, đôi, sám, sảnh (không có 2), tứ quý, ba đôi thông, bốn đôi thông.</p>
        <p>Chặt heo: ba đôi thông chặt một heo; tứ quý chặt heo hoặc đôi heo; bốn đôi thông chặt cả ngoài lượt. Tới trắng: tứ quý heo, sáu đôi, sảnh rồng, tứ quý 3 (ván đầu).</p>
        <p>Mỗi lượt 20 giây, hết giờ server đánh thay. Rời bàn / mất kết nối quá 20 giây giữa ván là bị loại.</p></div>`;
  }

  function seatAt(v, pos) { const me = v.me == null ? 0 : v.me; return (me + pos) % 4; }
  function secsLeft() { return st.deadline == null ? null : Math.max(0, Math.ceil((st.deadline - now()) / 1000)); }

  function viewSeat(v, seat, align) {
    const p = player(v, seat), g = v.game, t = now();
    const target = !!p && seat !== v.me && v.me != null && !st.watching;
    const current = g && g.current === seat && v.status === 'playing';
    if (!p) {
      return `<div class="tl-seat empty" id="tl-seat-${seat}"><span class="muted">Trống</span>${st.runaways[seat] > t ? '<span class="tl-slipper">🩴</span>' : ''}</div>`;
    }
    const delta = v.coin_deltas && v.coin_deltas[seat];
    const bal = v.balances && v.balances[seat];
    const placeOf = g && g.ranking && g.ranking.length ? (() => {
      const n = g.ranking.length;
      const i = g.ranking.findIndex((grp) => grp.includes(seat));
      return i < 0 ? null : { i: i + 1, n };
    })() : null;
    const placeLbl = placeOf ? (placeOf.i === placeOf.n && placeOf.n > 1 ? 'Bét' : PLACES[placeOf.i]) : '';
    const menu = target && st.throwMenu === seat && st.meta ? `<div class="tl-throw ${align}">${st.meta.throws.map((i) => `<button class="btn" data-tl="throw" data-item="${i.id}" title="${esc(i.name)} (${i.price} vàng)"><span>${i.emoji}</span><small>${i.price}</small></button>`).join('')}</div>` : '';
    return `<div class="tl-seat ${current ? 'current' : ''} ${target ? 'target' : ''}" id="tl-seat-${seat}" data-tl="seat" data-seat="${seat}" ${target ? 'data-target="1" title="Bấm để ném đồ"' : ''}>
      ${st.marks[seat] && st.marks[seat].until > t ? `<span class="tl-mark">${esc(st.marks[seat].text)}</span>` : ''}
      ${st.reactions[seat] && st.reactions[seat].until > t ? `<span class="tl-react">${esc(st.reactions[seat].emoji)}</span>` : ''}
      ${st.puffs[seat] > t ? '<span class="tl-puff">😮‍💨💨</span>' : ''}
      ${st.speech[seat] && st.speech[seat].until > t ? `<span class="tl-speech">💬 ${esc(st.speech[seat].text)}</span>` : ''}
      <div class="tl-name">${p.host ? '👑 ' : ''}${esc(p.name)}${seat === v.me ? ' <small class="muted">(bạn)</small>' : ''}${p.bot ? ' <span class="tag">🤖</span>' : ''}${p.connected ? '' : ' <span class="tag">mất kết nối</span>'}</div>
      ${bal != null ? `<div class="small num">💰 ${fmt(bal)}${delta ? ` <span class="tag ${delta > 0 ? 'good' : 'bad'}">${signed(delta)}</span>` : ''}</div>` : ''}
      ${p.bot && v.host === v.me && v.status === 'waiting' && !st.watching ? `<button class="btn small-btn" data-tl="remove-bot" data-seat="${seat}">Bỏ máy</button>` : ''}
      ${g && g.seats.includes(seat) ? `<div class="tl-seat-row">
        <span class="tl-backs">${cardImg('1B', 'back')}<b class="num">${g.card_counts[seat]}</b></span>
        ${g.passed.includes(seat) ? '<span class="tag">Bỏ lượt</span>' : ''}
        ${g.removed.includes(seat) ? '<span class="tag">Bị loại</span>' : ''}
        ${placeOf ? `<span>${MEDALS[placeOf.i] || ''} ${placeLbl}</span>` : ''}
        ${current && secsLeft() != null ? `<span class="tag tl-timer num" data-deadline="${st.deadline}">${secsLeft()}s</span>` : ''}
      </div>` : ''}
      ${menu}
    </div>`;
  }

  function viewCentre(v) {
    const g = v.game;
    if (g && g.centre) {
      return `<div class="tl-centre-cards">${g.centre.cards.map((c) => cardImg(c, 'mid')).join('')}</div>
        <p class="small">${esc(typeName(g.centre.type))} · ${esc(nameOf(g.centre.owner))}${g.centre.chop_context ? ' <span class="tag bad">chặt</span>' : ''}</p>`;
    }
    if (v.status === 'playing' && g) return `<p class="muted">Bàn trống — ${esc(nameOf(g.current))} đi trước</p>`;
    return '<p class="muted">Chưa bắt đầu</p>';
  }

  function sortedHand(hand) {
    const h = hand.slice();
    if (st.sort === 'suit') h.sort((a, b) => (parts(a).suit - parts(b).suit) || (parts(a).rank - parts(b).rank));
    else h.sort((a, b) => cardKey(a) - cardKey(b));
    return h;
  }

  function viewActions() {
    const v = st.view, g = v && v.game, c = st.checks || {};
    if (!v || v.status !== 'playing' || v.me == null || st.watching) return '<div id="tl-actions"></div>';
    const okPlay = c.play === 'ok', okPass = c.pass === 'ok', okChop = c.chop === 'ok' && g.current !== v.me;
    return `<div id="tl-actions" class="tl-actions">
      <button class="btn" data-tl="hint">Gợi ý</button>
      <button class="btn" data-tl="sort">${st.sort === 'rank' ? 'Xếp theo chất' : 'Xếp theo số'}</button>
      <button class="btn primary" data-tl="play" ${okPlay ? '' : 'disabled'}>${okPlay ? 'Đánh' : esc(c.play || 'Đánh')}</button>
      ${okPass ? '<button class="btn" data-tl="pass">Bỏ lượt</button>' : ''}
      ${okChop ? '<button class="btn danger" data-tl="chop">Chặt ngoài lượt!</button>' : ''}
      ${st.sel.size ? '<button class="btn" data-tl="clear">Bỏ chọn</button>' : ''}
    </div>`;
  }

  function viewResults(v) {
    const g = v.game;
    if (!g || !g.ranking || !g.ranking.length) return '';
    const n = g.ranking.length;
    const rows = g.ranking.map((grp, i) => grp.map((seat) => {
      const lbl = i + 1 === n && n > 1 ? 'Bét' : PLACES[i + 1];
      const d = v.coin_deltas && v.coin_deltas[seat];
      return `<div class="item"><span>${MEDALS[i + 1] || ''}</span><div class="grow">${esc(nameOf(seat))}</div><span class="small">${lbl}</span>${d ? `<span class="tag ${d > 0 ? 'good' : 'bad'} num">${signed(d)}</span>` : ''}</div>`;
    }).join('')).join('');
    const inst = (g.instant_winners || []).map((w) => `<div class="tl-instant"><b>${esc(nameOf(w.seat))}</b> tới trắng: ${esc(instName(w.type))}<div class="tl-centre-cards">${(w.hand || []).map((c) => cardImg(c, 'mini')).join('')}</div></div>`).join('');
    return `<div class="card tl-results"><h3>Kết quả ván ${v.games_played}</h3>${inst}<div class="list">${rows}</div></div>`;
  }

  function viewWaiting(v) {
    if (st.watching) return '<div class="card"><p class="muted">Đang chờ chủ phòng chia ván mới…</p></div>';
    const host = v.host === v.me;
    const free = v.players.length < 4;
    return `<div class="card tl-waiting">
      ${host ? `<button class="btn primary block" data-tl="start" ${v.players.length < 2 ? 'disabled' : ''}>Chia bài${v.players.length < 2 ? ' (cần ít nhất 2 người)' : ''}</button>
        <div class="tl-host-row">
          ${v.stake === 0 && free ? '<button class="btn" data-tl="add-bot" data-level="easy">+ Máy dễ</button><button class="btn" data-tl="add-bot" data-level="normal">+ Máy thường</button>' : ''}
          <button class="btn" data-tl="private">${v.private ? '🔓 Cho hiện ở sảnh' : '🔒 Ẩn khỏi sảnh'}</button>
        </div>
        ${v.players.some((p) => p.bot) ? '' : `<form data-tl-form="stake" class="tl-form row"><label class="small grow">Mức cược<input type="number" name="stake" min="0" step="10" value="${v.stake}"></label><button class="btn">Đổi</button></form>`}`
        : '<p class="muted">Chờ chủ phòng chia bài…</p>'}
      <p class="small muted">${v.stake ? `Cược ${fmt(v.stake)} vàng · cần ít nhất ${fmt(v.min_balance)} vàng để được chia bài.` : 'Chơi vui, không mất vàng.'} Mã phòng: <span class="tl-code">${esc(v.id)}</span> (gửi cho bạn để vào cùng).</p>
      <button class="btn" data-tl="blow" title="Thổi bài cho hên (không ảnh hưởng gì)">😮‍💨 Thổi bài</button>
    </div>`;
  }

  function viewChat() {
    if (st.watching) return '';
    const meta = st.meta || { phrases: [], reactions: [] };
    const lines = st.chat.map((m) => `<div class="tl-chat-line ${m.system ? 'system' : ''}">${m.system ? '' : `<b>${esc(m.name)}</b>: `}${esc(m.text)}</div>`).join('');
    return `<div class="tl-reacts">${meta.reactions.map((e) => `<button class="btn" data-tl="react" data-emoji="${e}">${e}</button>`).join('')}
        <button class="btn" data-tl="chat-toggle">💬 Chat${st.chatOpen ? ' ▲' : ' ▼'}</button></div>
      ${st.chatOpen ? `<div class="card tl-chat"><div class="tl-chat-log">${lines || '<p class="small muted">Chưa có tin nào.</p>'}</div>
        <div class="tl-phrases">${meta.phrases.map((p) => `<button class="btn small-btn" data-tl="phrase" data-text="${esc(p)}">${esc(p)}</button>`).join('')}</div>
        <form data-tl-form="chat" class="row"><input name="text" maxlength="200" class="grow" placeholder="Nhắn cả bàn…" autocomplete="off"><button class="btn">Gửi</button></form></div>` : ''}`;
  }

  function viewTable(watching) {
    const v = st.view, g = v.game, t = now();
    const right = `<button class="btn" data-tl="sound" title="Âm thanh">${window.Sound && window.Sound.on ? '🔊' : '🔇'}</button>
      ${watching ? '<button class="btn" data-tl="lobby">Thôi xem</button>' : '<button class="btn" data-tl="lobby">Sảnh</button><button class="btn danger" data-tl="leave">Rời bàn</button>'}`;
    const info = `<p class="small tl-info">Phòng <span class="tl-code">${esc(v.id)}</span> · ván đã chơi: ${v.games_played} · <span class="tag">${v.stake ? `Cược ${fmt(v.stake)} (cần ${fmt(v.min_balance)})` : 'Chơi vui'}</span>${v.private ? ' <span class="tag">Riêng</span>' : ''}${v.spectators ? ` · 👀 ${v.spectators}` : ''}${watching ? ' · <b>Đang xem</b>' : ''}</p>`;
    const hand = g && v.me != null ? sortedHand(g.hand || []) : [];
    const handHtml = v.status === 'playing' && v.me != null && !watching ? `
      ${g.must_include ? `<p class="tl-must">Nước đầu phải có ${cardLabel(g.must_include)}</p>` : ''}
      <div class="tl-hand" id="tl-hand">${hand.map((c) => `<button class="tl-slot ${st.sel.has(c) ? 'sel' : ''}" data-tl="card" data-card="${c}" aria-pressed="${st.sel.has(c)}">${cardImg(c)}</button>`).join('')}</div>
      ${viewActions()}` : '';
    return `${head('🃏 Tiến Lên', right)}${info}
      <div class="tl-table">
        <div class="tl-pos top">${viewSeat(v, seatAt(v, 2), 'center')}</div>
        <div class="tl-pos left">${viewSeat(v, seatAt(v, 3), 'left')}</div>
        <div class="tl-pos right">${viewSeat(v, seatAt(v, 1), 'right')}</div>
        <div class="tl-pos centre tl-felt">${viewCentre(v)}</div>
        <div class="tl-pos me">${viewSeat(v, seatAt(v, 0), 'center')}</div>
      </div>
      ${st.ticker && st.ticker.until > t ? `<p class="tl-ticker" aria-live="polite">${esc(st.ticker.text)}</p>` : ''}
      ${v.status === 'waiting' && g ? viewResults(v) : ''}
      ${v.status === 'waiting' ? viewWaiting(v) : ''}
      ${handHtml}
      ${viewChat()}`;
  }

  function viewHistory() {
    const rows = st.games.map((g) => {
      const names = g.players.map((p) => esc(p.name || (p.bot ? 'Máy' : '?'))).join(', ');
      return `<div class="item"><div class="grow"><div class="name">${g.place ? (MEDALS[g.place] || '') + ' ' + (g.place === g.players.length && g.place > 1 ? 'Bét' : PLACES[g.place]) : '—'} · ${names}</div>
        <div class="small muted">${new Date(g.at).toLocaleString('vi-VN')}${g.coins ? ` · <span class="${g.coins > 0 ? 'up' : 'down'}">${signed(g.coins)} vàng</span>` : ''}</div></div>
        <button class="btn" data-tl="replay" data-id="${g.id}">▶ Xem lại</button></div>`;
    }).join('');
    return `${head('📜 Ván đã chơi', '<button class="btn" data-tl="lobby">Sảnh</button>')}
      <div class="card"><div class="list">${rows || '<p class="small muted">Chưa có ván nào.</p>'}</div></div>`;
  }

  function describe(e, names) {
    const n = (s) => esc(names[s] || `Ghế ${s + 1}`);
    switch (e.type) {
      case 'deal': return 'Chia bài';
      case 'played': return `${n(e.seat)} đánh ${esc(typeName(e.combo))} ${e.cards.map(cardLabel).join(' ')}`;
      case 'chopped': return `${n(e.seat)} chặt ngoài lượt bằng ${esc(typeName(e.combo))}!`;
      case 'passed': return `${n(e.seat)} bỏ lượt`;
      case 'timed_out': return `${n(e.seat)} hết giờ`;
      case 'round_ended': return 'Hết vòng, dọn bàn';
      case 'lead_moved': return `${n(e.seat)} đi tiếp`;
      case 'finished': return `${n(e.seat)} về ${PLACES[e.place] || e.place}`;
      case 'removed': return `${n(e.seat)} bị loại`;
      case 'instant_win': return `Tới trắng: ${e.winners.map((w) => `${n(w[0])} (${esc(instName(w[1]))})`).join(', ')}`;
      case 'coins': return `Trả vàng: ${e.transfers.map((x) => `${n(x.from)} → ${n(x.to)} ${fmt(x.amount)}`).join('; ')}`;
      case 'game_over': return 'Hết ván';
      default: return esc(e.type);
    }
  }

  function viewReplay() {
    const r = st.replay, f = r.frames[st.frame], names = r.names || {};
    const seats = Object.keys(f.hands).map(Number).sort((a, b) => a - b);
    const hands = seats.map((s) => `<div class="tl-rp-hand ${f.centre && f.centre.seat === s ? 'owner' : ''}">
        <div class="small"><b>${esc(names[s] || `Ghế ${s + 1}`)}</b>${f.passed.includes(s) ? ' <span class="tag">bỏ lượt</span>' : ''}${f.finished.includes(s) ? ` <span class="tag good">về ${PLACES[f.finished.indexOf(s) + 1]}</span>` : ''}${f.removed.includes(s) ? ' <span class="tag">bị loại</span>' : ''}</div>
        <div class="tl-centre-cards">${f.hands[s].slice().sort((a, b) => cardKey(a) - cardKey(b)).map((c) => cardImg(c, 'mini')).join('') || '<span class="muted small">hết bài</span>'}</div></div>`).join('');
    const n = r.frames.length - 1;
    return `${head(`▶ Xem lại ván #${r.id}`, '<button class="btn" data-tl="history">‹ Danh sách</button>')}
      <div class="card"><p class="tl-ev"><b>${st.frame}/${n}</b> · ${describe(f.event, names)}</p>
        <div class="tl-felt tl-rp-centre">${f.centre ? `<div class="tl-centre-cards">${f.centre.cards.map((c) => cardImg(c, 'mid')).join('')}</div><p class="small">${esc(typeName(f.centre.type))} · ${esc(names[f.centre.seat] || '')}${f.centre.chop ? ' <span class="tag bad">chặt</span>' : ''}</p>` : '<p class="muted">Bàn trống</p>'}</div>
        <div class="tl-rp-controls"><button class="btn" data-tl="frame" data-to="first">⏮</button><button class="btn" data-tl="frame" data-to="prev">◀</button>
          <button class="btn primary" data-tl="autoplay">${st.playing ? '⏸' : '▶'}</button><button class="btn" data-tl="frame" data-to="next">▶</button><button class="btn" data-tl="frame" data-to="last">⏭</button></div></div>
      <div class="card">${hands}</div>`;
  }

  // đồng hồ lượt, biểu cảm / dấu ném hết hạn
  setInterval(() => {
    if (!st.open || !root) return;
    const t = now();
    root.querySelectorAll('[data-deadline]').forEach((el) => { el.textContent = Math.max(0, Math.ceil((+el.dataset.deadline - t) / 1000)) + 's'; });
    const v = st.view;
    if (v && v.status === 'playing' && v.me != null && v.game && v.game.current === v.me && !st.watching) {
      const s = secsLeft();
      if (s != null && s > 0 && s <= 5 && s !== st.lastTick) { st.lastTick = s; sound('notice'); }
    }
    const expired = (o) => Object.keys(o).some((k) => (typeof o[k] === 'number' ? o[k] : o[k].until) <= t);
    const clean = (o) => { Object.keys(o).forEach((k) => { if ((typeof o[k] === 'number' ? o[k] : o[k].until) <= t) delete o[k]; }); };
    const dirty = expired(st.reactions) || expired(st.marks) || expired(st.speech) || expired(st.puffs) || expired(st.runaways)
      || (st.ticker && st.ticker.until <= t) || (st.msg && st.msg.until <= t);
    if (dirty) {
      [st.reactions, st.marks, st.speech, st.puffs, st.runaways].forEach(clean);
      if (st.ticker && st.ticker.until <= t) st.ticker = null;
      if (st.msg && st.msg.until <= t) st.msg = null;
      if (!document.activeElement || !root.contains(document.activeElement) || document.activeElement.tagName !== 'INPUT') render();
    }
  }, 500);

  function init() {
    if (!window.Net) return;
    window.Net.onTl(onTl);
    window.Net.onTlChat(onChat);
    window.Net.onTlFx(onFx);
    window.Net.onTlLobby(() => { if (st.open && st.screen === 'lobby') loadLobby(); });
  }

  window.TL = {
    open, close, init,
    isOpen: () => st.open,
    // cho e2e: trạng thái hiện tại (không có bài người khác vì server không gửi)
    state: () => JSON.parse(JSON.stringify({ screen: st.screen, roomId: st.roomId, watching: st.watching, view: st.view, sel: [...st.sel], checks: st.checks })),
  };
})();

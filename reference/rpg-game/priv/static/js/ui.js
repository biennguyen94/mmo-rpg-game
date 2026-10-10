/* Giao diện: vẽ lại từng màn hình từ trạng thái người chơi (P) do server gửi về.
 * Mọi thao tác gửi lên server qua Net (net.js); server tính toán rồi trả trạng thái mới.
 * P.view chứa các chỉ số server tính sẵn (máu tối đa, tấn công, giá nghỉ trọ...). */
(function () {
  const { CLASSES, ZONES, ITEMS, RULES, RECIPES, QUESTS, WORLD, ACHIEVEMENTS, PETS, FURNITURE, UPGRADE, CHAOS } = window.GAME_DATA;
  const Net = window.Net;
  const L = window.HLLogic; // hàm thuần (logic.js), có test node --test

  let P = null;          // trạng thái người chơi
  let tab = 'map';       // tab đang mở
  let pickCls = 'dk';
  let confirmReset = false;
  let confirmRebirth = false;
  let fx = null;         // hiệu ứng trận đấu của lượt vừa rồi
  let authMode = 'login'; // 'login' | 'register'
  let loading = true;    // đang kết nối server
  let busy = false;      // đang chờ server trả lời
  let walk = null;       // đích đang đi tới trên bản đồ: { x, y, monster, id }
  let friendsUi = { open: false, data: null, chat: null, dm: 0 }; // bạn bè; chat: { uid, data }
  let trade = null;      // giao dịch trực tiếp (HacLong.Trade.view): { partner_name, status, incoming, mine, theirs, my_ready, their_ready }
  let profileUi = { open: false, info: null }; // Phase 13: hồ sơ người chơi (mình hoặc người khác)
  let visit = null;      // đang thăm nhà: { uid, info: null | { id, name, look, decor, comfort, likes, liked } }
  let dialog = null;    // bảng trên bản đồ: { type: 'boss', dir, boss } | { type: 'waystone' }
  let npc = null;        // NPC đang nói chuyện: { map, id, line }
  let pwForm = false;    // đang mở form đổi mật khẩu
  let chats = [];        // tin chat gần nhất
  let chatDraft = '';    // chữ đang gõ dở (giữ lại khi vẽ lại trang)
  let board = { kind: 'level', cls: null, data: null, at: 0 }; // bảng xếp hạng (cls: lọc theo lớp ở bảng Cấp cao)
  let chatMenu = null;   // id tin nhắn đang mở menu Báo cáo/Chặn
  let blocked = [];      // người mình đã chặn: [{ id, name }]
  let adm = { reports: null, user: null, loading: false, audit: null, alog: null, glog: null, online: null }; // tab Quản trị
  let mail = { unread: 0, list: null, open: false, filter: 'all' }; // hộp thư (filter: all | unread | gift)
  let guildUi = { open: false, list: null, requested: [], info: null, q: '', confirm: null }; // bang hội
  let chatTo = 'world';  // 'world' | 'guild' | 'party'
  let party = null;      // tổ đội: { id, leader, members: [{ id, name, level, hp, maxHp, map }], max }
  let arena = null;
  let pk = null; // { invite, history, today, rules } (PK cược vàng)
  let market = { tab: 'buy', data: null, q: '', loading: false }; // chợ ở Chủ Chợ      // đấu trường: { me, suggestions, top }
  let fishing = null;
  let sharedN = 1;       // số người trong trận đánh chung đang đánh
  let decor = { on: false, pick: null }; // trang trí nhà: đang bật, món đang chọn để đặt    // lượt câu: { phase: 'wait' | 'bite', timers: [] }
  let wb = { alive: false }; // trùm thế giới; `skew`: lệch đồng hồ máy chủ - máy này
  const Map_ = window.MapView;
  const Sound = window.Sound;

  const $ = (s) => document.querySelector(s);
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fmt = (n) => Math.round(n).toLocaleString('vi-VN');

  const asset = (path) => 'assets/' + path;
  const icon = (name, cls) => `<img class="ic ${cls || ''}" src="${asset('icons/' + name + '.svg')}" alt="">`;
  // Hình vật phẩm: nguyên liệu dùng ảnh PNG (`sprite`), còn lại dùng icon SVG.
  // Hình riêng của đồ theo cấp nâng (bộ hình của anh, `mix hac_long.icons`): khóa `ref` ("nhóm/số"
  // trong Item.txt) hoặc "custom/{id}"; lấy mức lớn nhất ≤ cấp. Không có thì dùng icon / sprite cũ.
  const ITEM_ICONS = window.GAME_DATA.ITEM_ICONS || {};
  function ownIcon(it, level) {
    const path = L.iconForLevel(ITEM_ICONS[it.ref] || ITEM_ICONS['custom/' + (it.base || it.id)], level);
    return path ? asset(path) : null;
  }
  const itemIcon = (it, rarity, level) => { const own = ownIcon(it, level); return own ? `<img class="ic lg own" src="${own}" alt="">` : it.sprite ? `<img class="ic lg px" src="${asset(it.sprite + '.png')}" alt="">` : icon(it.icon, 'lg' + (rarity ? ` rar-ic-${rarity}` : '')); };
  // hình nhân vật mặc đúng đồ đang trang bị (doll.js)
  const heroSprite = (cls) => `<img class="sprite ${cls || ''}" src="${window.Doll.url(P && P.view.look)}" alt="${esc(P ? P.name : '')}">`;
  const sprite = (id, cls, alt) => `<img class="sprite ${cls || ''}" src="${asset('monsters/' + id + '.png')}" alt="${esc(alt || '')}">`;

  // ---------- Thông báo (Phase 8, L2) ----------
  // Tin đáng nhớ (ép +N, ghép, thư, lời mời, kết quả cược, tin hệ thống…) giữ lại để xem sau. Chỉ ở trình duyệt
  // này (localStorage theo tài khoản, tối đa 50 tin); mất thì thôi, server không cần biết.
  let notes = { list: [], open: false };
  const notesKey = () => `hl-notes-${Net.userId}`;
  function loadNotes() {
    try { notes.list = JSON.parse(localStorage.getItem(notesKey()) || '[]'); } catch (e) { notes.list = []; }
  }
  function saveNotes() {
    try { localStorage.setItem(notesKey(), JSON.stringify(notes.list)); } catch (e) { /* bộ nhớ trình duyệt bị chặn: chỉ giữ trong phiên */ }
  }
  function note(text, kind) {
    if (!text) return;
    notes.list = [{ text, kind: kind || 'info', at: Date.now(), read: notes.open }].concat(notes.list).slice(0, 50);
    saveNotes();
    refreshHud();
  }
  const notesUnread = () => notes.list.filter((n) => !n.read).length;
  function viewNotes() {
    const icons = { good: '✨', bad: '💥', mail: '✉', invite: '🤝', info: '🔔' };
    return `<div class="row"><h2 class="display grow">Thông báo</h2>${notes.list.length ? '<button class="btn" data-act="notes-clear">Xóa hết</button>' : ''}<button class="btn" data-act="notes-close">Đóng</button></div>
      ${notes.list.length ? `<div class="list" id="notes-list">${notes.list.map((n) => `<div class="item note ${n.read ? 'read' : ''}"><span>${icons[n.kind] || '🔔'}</span><div class="grow"><div>${esc(n.text)}</div><div class="small muted">${new Date(n.at).toLocaleString('vi-VN')}</div></div></div>`).join('')}</div>`
        : '<div class="card"><p class="small muted">Chưa có thông báo nào. Ép đồ thành công, thư mới, lời mời, kết quả cược… sẽ hiện ở đây.</p></div>'}`;
  }

  // ---------- Hiệu ứng lớn giữa màn hình (Phase 8, M11) ----------
  // "LÊN CẤP", ép thành công / vỡ đồ, ghép cánh, hồi máu: chữ to bay lên rồi tắt; tôn trọng "giảm chuyển động".
  function bigFx(text, kind) {
    if (!text) return;
    const el = document.createElement('div');
    el.className = `bigfx ${kind || ''}`;
    el.setAttribute('aria-hidden', 'true');
    el.textContent = text;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 1600);
  }
  // hiệu ứng theo kết quả một lệnh
  function resultFx(cmd, r, old) {
    if (!r || !r.ok || !P) return;
    if (old && P.level > old.level) { bigFx(`LÊN CẤP ${P.level}!`, 'level'); note(`Lên cấp ${P.level}.`, 'good'); }
    const up = r.upgrade, ch = r.chaos, life = r.life;
    if (up) {
      if (up.result === 'success') bigFx(`✨ +${up.level || ''}`.trim(), 'good');
      else if (up.result === 'destroyed' || up.result === 'destroy') bigFx('💥 VỠ ĐỒ', 'bad');
      else bigFx('THẤT BẠI', 'bad');
      if (up.result !== 'success' || (up.level || 0) >= 7) note(r.msg, up.result === 'success' ? 'good' : 'bad');
    }
    if (ch) { bigFx(ch.result === 'fail' ? '💥 THẤT BẠI' : '✨ THÀNH CÔNG', ch.result === 'fail' ? 'bad' : 'good'); note(r.msg, ch.result === 'fail' ? 'bad' : 'good'); }
    if (life) bigFx(life.result === 'success' ? '💚 +1 dòng' : '💔 THẤT BẠI', life.result === 'success' ? 'good' : 'bad');
    if (old && ['use', 'rest', 'potion'].includes(cmd.act)) {
      const hp = P.hp - old.hp, mp = (P.mp || 0) - (old.mp || 0);
      if (hp > 0 || mp > 0) bigFx([hp > 0 ? `+${fmt(hp)} máu` : '', mp > 0 ? `+${fmt(mp)} MP` : ''].filter(Boolean).join('  '), 'heal');
    }
  }

  let toastTimer;
  function toast(msg, err) {
    if (!msg) return;
    const t = $('#toast');
    t.textContent = msg;
    t.className = 'show' + (err ? ' err' : '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.className = err ? 'err' : ''; }, 1800);
  }

  function result(r) {
    if (!r) return;
    // ép / ghép thất bại vẫn là lệnh hợp lệ (ok) nhưng hiện như tin xấu
    const failed = (r.upgrade && r.upgrade.result !== 'success') || (r.chaos && r.chaos.result === 'fail') || (r.life && r.life.result === 'fail');
    if (!r.ok) toast(r.msg, true); else if (r.msg) toast(r.msg, failed);
  }

  // ---------- Khung ----------
  // Không khí nhạc nền theo nơi đang đứng, giờ trong ngày và trận đánh.
  function musicMood() {
    if (!P || loading || !Net.username) return null;
    const b = P.battle;
    if (b && !b.over) return b.monster.boss || b.monster.world ? 'boss' : 'battle';
    const map = P.pos.map, phase = Map_.world().phase;
    if (map === 'home') return 'home';
    if (map === 'tower') return 'tower';
    if (phase === 'night') return 'night';
    return map === 'village' ? 'village' : 'wild';
  }

  function render() {
    hideTip();
    Sound.music(musicMood());
    const hud = $('#hud'), tabs = $('#tabs'), view = $('#view');
    if (loading || !Net.username) {
      hud.hidden = true; tabs.hidden = true;
      view.innerHTML = loading ? viewLoading() : viewLogin();
      return;
    }
    if (!P) {
      hud.hidden = true; tabs.hidden = true;
      view.innerHTML = viewCreate();
      return;
    }
    hud.hidden = false;
    hud.innerHTML = viewHud();
    if (P.battle) {
      tabs.hidden = true;
      view.classList.add('fit');
      view.innerHTML = viewBattle();
      const log = view.querySelector('.log');
      if (log) log.scrollTop = log.scrollHeight;
      fx = null;
      return;
    }
    tabs.hidden = false;
    // dock (Phase 9, U3): Bản đồ, Nhân vật, Túi đồ, Chọn bản đồ, Menu
    tabs.innerHTML = [
      ['map', 'walk', 'Bản đồ'],
      ['hero', 'person', 'Nhân vật'],
      ['bag', 'backpack', 'Túi đồ'],
      ['travel', 'dungeon-gate', 'Chọn map'],
      ['people', '<span class="ic dock-emoji" aria-hidden="true">👫</span>', 'Quanh đây'],
      ['menu', 'open-book', 'Menu'],
    ].map(([id, ic, label]) => `<button data-tab="${id}" ${TAB_KEY[id] ? `title="${label} (phím ${TAB_KEY[id]})" aria-keyshortcuts="${TAB_KEY[id]}"` : ''} ${tab === id ? 'aria-current="page"' : ''}>${ic.startsWith('<') ? ic : icon(ic)}<span>${label}${id === 'people' ? peopleDot() : ''}${id === 'hero' && P.points ? `<span class="points-dot">${P.points}</span>` : ''}</span></button>`).join('');
    const trading = trade && trade.status !== 'pending';
    // U5: bản đồ vừa khít giữa HUD và dock, không cuộn trang
    view.classList.toggle('fit', tab === 'map' && !npc && !trading && !profileUi.open && !visit && !friendsUi.open && !notes.open && !mail.open && !guildUi.open);
    view.innerHTML = trading ? viewTrade() : profileUi.open ? viewProfile() : visit ? viewVisit() : friendsUi.open ? viewFriends() : notes.open ? viewNotes() : mail.open ? viewMail() : guildUi.open ? viewGuild() : ({ map: () => (npc ? viewNpc() : viewTutorial() + viewDecorPanel() + Map_.html(P, viewDialog() + viewFishing() + viewDecorButton() + viewChat()) + viewParty()), hero: viewHero, bag: viewBag, travel: viewTravel, people: viewPeople, menu: viewMenu }[tab] || viewMenu)();
    if (trading) {
      // bảng giao dịch che bản đồ
    } else if (visit) {
      const c = $('#visit-canvas');
      if (c && visit.info) Map_.drawHome(c, visit.info);
    } else if (friendsUi.open) {
      const log = $('#dm-log');
      if (log) log.scrollTop = log.scrollHeight;
    } else if (tab === 'map' && !npc && !mail.open && !guildUi.open) {
      Map_.mount(() => P);
      Map_.setRelations(() => ({
        party: party ? party.members.map((m) => m.id) : [],
        tag: P && P.guild && P.guild.tag,
        enemy: P && P.guild && P.guild.war && P.guild.war.enemy && P.guild.war.enemy.tag,
      }));
      const log = $('#chat-log');
      if (log) log.scrollTop = log.scrollHeight;
    }
    if (onMenu('arena')) loadArena();
    if (onMenu('board')) loadBoard();
    if (onMenu('admin') && adm.reports == null && !adm.loading) loadReports();
  }

  // ---------- Quản trị ----------
  const vnTime = (t) => (!t ? '' : new Date(t).getFullYear() >= 9999 ? 'vĩnh viễn' : 'đến ' + new Date(t).toLocaleString('vi-VN'));

  async function loadReports() {
    adm.loading = true;
    try { adm.reports = (await Net.admin('reports')).reports; } catch (e) { toast(e.msg, true); }
    adm.loading = false;
    if (onMenu('admin')) render();
  }

  function viewAdmin() {
    const reports = adm.reports == null ? '<p class="small muted">Đang tải…</p>'
      : adm.reports.length === 0 ? '<p class="small muted">Không có báo cáo nào chưa xử lý.</p>'
      : `<div class="list">${adm.reports.map((r) => `<div class="item quest"><div class="grow">
          <div class="name">${esc(r.target)}</div>
          <div>“${esc(r.text)}”</div>
          <div class="small muted">Báo cáo bởi ${esc(r.reporter)} · ${new Date(r.at).toLocaleString('vi-VN')}</div>
          <div class="btn-row"><button class="btn small-btn" data-adm="resolve" data-id="${r.id}" data-action="dismiss">Bỏ qua</button>
            <button class="btn small-btn" data-adm="resolve" data-id="${r.id}" data-action="mute" data-minutes="60">Cấm chat 1 giờ</button>
            <button class="btn small-btn danger" data-adm="resolve" data-id="${r.id}" data-action="ban" data-minutes="1440">Khóa 1 ngày</button></div>
        </div></div>`).join('')}</div>`;
    const u = adm.user;
    const user = !u ? '' : `<div class="card">
        <div class="row"><h3 class="grow">${esc(u.character ? u.character.name : u.username)}</h3><span class="small muted">@${esc(u.username)}</span></div>
        <p class="small">${u.character ? `Cấp ${u.character.level} · ${fmt(u.character.gold)} vàng · ${fmt(u.character.kills)} quái` : 'Chưa có nhân vật'} · bị báo cáo ${u.reports} lần</p>
        <p class="small">${u.banned_until ? `<span style="color:var(--bad)">Bị khóa ${vnTime(u.banned_until)}${u.ban_reason ? ': ' + esc(u.ban_reason) : ''}</span>` : 'Không bị khóa'} · ${u.muted_until ? `<span style="color:var(--bad)">Bị cấm chat ${vnTime(u.muted_until)}</span>` : 'Được chat'}</p>
        <div class="btn-row">
          <button class="btn small-btn" data-adm="mute" data-uid="${u.id}" data-minutes="60">Cấm chat 1 giờ</button>
          <button class="btn small-btn" data-adm="mute" data-uid="${u.id}" data-minutes="1440">Cấm chat 1 ngày</button>
          <button class="btn small-btn" data-adm="unmute" data-uid="${u.id}">Bỏ cấm chat</button>
        </div>
        ${isAdminRole() ? `<div class="btn-row">
          <button class="btn small-btn danger" data-adm="ban" data-uid="${u.id}" data-minutes="1440">Khóa 1 ngày</button>
          <button class="btn small-btn danger" data-adm="ban" data-uid="${u.id}">Khóa vĩnh viễn</button>
          <button class="btn small-btn" data-adm="unban" data-uid="${u.id}">Mở khóa</button>
        </div>
` : ''}
      </div>
      ${isAdminRole() && u.character ? viewCharEdit(u) : ''}`;
    return `<h2 class="display">Quản trị</h2>
      <div class="card"><div class="row"><h3 class="grow">Báo cáo chưa xử lý</h3><button class="btn small-btn" data-adm="reload">Tải lại</button></div>${reports}</div>
      <div class="card" id="adm-online"><div class="row"><h3 class="grow">Đang online${adm.online ? `: ${adm.online.count}` : ''}</h3><button class="btn small-btn" data-adm="online">${adm.online ? 'Tải lại' : 'Xem'}</button></div>
        ${adm.online ? (adm.online.players.length ? `<div class="list">${adm.online.players.map((o) => `<div class="item"><div class="grow"><div class="name">${esc(o.name)}</div><div class="small muted">${CLASSES[o.cls] ? CLASSES[o.cls].name : ''} · cấp ${o.level} · ${esc((WORLD.maps[o.map] || {}).name || o.map)}</div></div><button class="btn small-btn" data-adm="online-lookup" data-name="${esc(o.name)}">Tra</button></div>`).join('')}</div>` : '<p class="small muted">Không có ai.</p>') : ''}
      </div>
      <div class="card"><h3>Tra cứu người chơi</h3>
        <form id="adm-lookup" class="chat-form"><input type="text" id="adm-name" placeholder="Tên nhân vật hoặc tên đăng nhập" autocomplete="off"><button class="btn" type="submit">Tìm</button></form>
      </div>
      ${user}
      <div class="card"><h3>Thông báo cho cả server</h3>
        <form id="adm-announce" class="chat-form"><input type="text" id="adm-text" maxlength="200" placeholder="Nội dung thông báo" autocomplete="off"><button class="btn" type="submit">Gửi</button></form>
      </div>
      ${isAdminRole() ? `<div class="card"><h3>Quà cho mọi người</h3><p class="small muted">Gửi vào hộp thư của mọi nhân vật (vd. đền bù bảo trì).</p>${giftForm('adm-gift-all')}</div>
      <div class="card"><h3>Trùm thế giới</h3><button class="btn" data-adm="world_boss">Gọi Cổ Long xuất hiện ngay</button></div>
      <div class="card"><h3>Golden Invasion</h3><button class="btn" data-adm="invasion">Bắt đầu ngay</button></div>
      ${viewAudit()}
      <div class="card"><div class="row"><h3 class="grow">Nhật ký quản trị</h3><button class="btn small-btn" data-adm="admin_log">Xem 50 dòng mới nhất</button></div>${adm.alog && !adm.alog.uid ? viewAdminLog(adm.alog.log) : ''}</div>` : ''}`;
  }

  const isAdminRole = () => Net.role === 'admin';
  const STAT_KEYS = [['str', 'Sức mạnh'], ['agi', 'Nhanh nhẹn'], ['vit', 'Thể lực'], ['ene', 'Năng lượng']];
  const vnDate = (t) => new Date(t).toLocaleString('vi-VN');

  // Chỉnh nhân vật (chỉ admin): mỗi dòng là một form `adm-char` với `data-op` (HacLong.Admin).
  function viewCharEdit(u) {
    const all = Object.entries(ITEMS);
    const gearBases = all.filter(([, it]) => ['weapon', 'armor', 'shield'].includes(it.slot));
    const up = '<label class="small">+ <input type="number" name="up" min="0" max="5" value="0"></label>';
    const line = (op, label, inner, btn = 'Làm') => `<form class="adm-char gift-form" data-op="${op}" data-uid="${u.id}"><div class="btn-row"><span class="small grow">${label}</span>${inner}<button class="btn small-btn" type="submit">${btn}</button></div></form>`;
    const num = (name, value, attrs = '') => `<input type="number" name="${name}" value="${value}" ${attrs}>`;
    return `<div class="card"><h3>Chỉnh nhân vật</h3>
      <p class="small muted">Sửa ngay (người chơi đang online thấy liền), ghi vào nhật ký quản trị và nhật ký vàng/đồ với lý do ADMIN.</p>
      ${line('give_xp', 'Kinh nghiệm', num('xp', 1000, 'min="1"'), 'Cộng')}
      ${line('set_level', 'Đặt cấp', num('level', u.character.level, 'min="1" max="50"'), 'Đặt')}
      ${line('add_gold', 'Vàng (âm để trừ)', num('amount', 1000), 'Cộng')}
      ${line('add_points', 'Điểm tiềm năng (âm để trừ)', num('n', 10), 'Cộng')}
      ${line('add_stats', 'Chỉ số (âm để trừ)', STAT_KEYS.map(([k, l]) => `<label class="small" title="${l}">${k} ${num(k, 0)}</label>`).join(''), 'Cộng')}
      ${line('give_item', 'Đồ thường', `<select name="id">${all.map(([k, it]) => `<option value="${k}">${esc(it.name)}${it.drop ? ' (rơi trùm)' : it.price ? '' : ' (không bán)'}</option>`).join('')}</select>${num('count', 1, 'min="1" max="9999" aria-label="Số lượng"')}${up}`, 'Tặng')}
      ${line('give_gear', 'Đồ hiếm', `<select name="base">${gearBases.map(([k, it]) => `<option value="${k}">${esc(it.name)}</option>`).join('')}</select><select name="rarity"><option value="3">Sử Thi</option><option value="2">Hiếm</option><option value="1">Tốt</option></select>${STAT_KEYS.map(([k, l]) => `<label class="small" title="${l} (để 0 cả bốn: tự chọn)">${k} ${num(k, 0, 'min="0"')}</label>`).join('')}${up}`, 'Tặng')}
      <div class="btn-row"><button class="btn small-btn" data-adm="heal" data-uid="${u.id}">Hồi đầy máu</button>
        <button class="btn small-btn" data-adm="gold_log" data-uid="${u.id}">Nhật ký vàng</button>
        <button class="btn small-btn" data-adm="admin_log" data-uid="${u.id}">Nhật ký quản trị</button></div>
      ${adm.glog && adm.glog.uid === u.id ? viewGoldLog(adm.glog.log) : ''}
      ${adm.alog && adm.alog.uid === u.id ? viewAdminLog(adm.alog.log) : ''}
    </div>`;
  }

  function viewGoldLog(log) {
    if (!log.length) return '<p class="small muted">Chưa có nhật ký vàng.</p>';
    return `<table class="adm-table"><tr><th>Lúc</th><th>Lý do</th><th>Đổi</th><th>Còn</th></tr>${log.map((l) => `<tr><td>${vnDate(l.at)}</td><td>${esc(l.reason)}${l.ref ? ` <span class="muted">${esc(l.ref)}</span>` : ''}</td><td style="color:var(${l.delta < 0 ? '--bad' : '--good'})">${l.delta > 0 ? '+' : ''}${fmt(l.delta)}</td><td>${fmt(l.balance)}</td></tr>`).join('')}</table>`;
  }

  function viewAdminLog(log) {
    if (!log.length) return '<p class="small muted">Chưa có thao tác nào.</p>';
    return `<table class="adm-table"><tr><th>Lúc</th><th>Ai</th><th>Lệnh</th><th>Kết quả</th></tr>${log.map((l) => `<tr><td>${vnDate(l.at)}</td><td>${esc(l.admin)}</td><td>${esc(l.op)}${l.target_id ? ` <span class="muted">#${l.target_id}</span>` : ''}<div class="small muted">${esc(JSON.stringify(l.params))}</div></td><td>${esc(l.result || '')}</td></tr>`).join('')}</table>`;
  }

  function viewAudit() {
    const a = adm.audit;
    const body = !a ? '' : `${a.problems.length === 0 ? '<p class="small" style="color:var(--good)">Không có lỗi: vàng khớp nhật ký, không có đồ hiếm trùng.</p>'
      : `<p class="small" style="color:var(--bad)">${a.problems.length} lỗi:</p><ul class="small">${a.problems.map((p) => `<li>[${esc(p.kind)}] ${esc(p.text)}</li>`).join('')}</ul>`}
      <h4>Vàng ${a.stats.days} ngày qua theo lý do</h4>
      ${a.stats.by_reason.length ? `<table class="adm-table"><tr><th>Lý do</th><th>Vào</th><th>Ra</th><th>Lần</th></tr>${a.stats.by_reason.map((r) => `<tr><td>${esc(r.reason)}</td><td>+${fmt(r.in)}</td><td>${fmt(r.out)}</td><td>${r.n}</td></tr>`).join('')}</table>` : '<p class="small muted">Không có.</p>'}
      <h4>Nhận nhiều vàng nhất</h4>
      ${a.stats.top.length ? `<ol class="small">${a.stats.top.map((t) => `<li>${esc(t.name || '(đã xóa) #' + t.user_id)}: +${fmt(t.gold)}</li>`).join('')}</ol>` : '<p class="small muted">Không có.</p>'}`;
    return `<div class="card"><div class="row"><h3 class="grow">Kiểm tra vàng</h3>
      <button class="btn small-btn" data-adm="audit" data-days="1">1 ngày</button><button class="btn small-btn" data-adm="audit" data-days="7">7 ngày</button></div>
      <p class="small muted">Đối soát vàng của mọi nhân vật với nhật ký, tìm đồ hiếm trùng mã (dấu hiệu nhân đồ). Như lệnh <code>mix hac_long.audit</code>.</p>${body}</div>`;
  }

  function onCharOp(form) {
    const f = new FormData(form), op = form.dataset.op, payload = { uid: +form.dataset.uid };
    const n = (k) => Math.trunc(+f.get(k) || 0);
    if (op === 'give_xp') payload.xp = n('xp');
    if (op === 'set_level') payload.level = n('level');
    if (op === 'add_gold') payload.amount = n('amount');
    if (op === 'add_points') payload.n = n('n');
    if (op === 'add_stats') STAT_KEYS.forEach(([k]) => { if (n(k)) payload[k] = n(k); });
    if (op === 'give_item') Object.assign(payload, { id: f.get('id'), count: n('count') || 1, up: n('up') });
    if (op === 'give_gear') {
      Object.assign(payload, { base: f.get('base'), rarity: n('rarity'), up: n('up') });
      const bonus = {};
      STAT_KEYS.forEach(([k]) => { if (n(k) > 0) bonus[k] = n(k); });
      if (Object.keys(bonus).length) payload.bonus = bonus;
    }
    Net.admin(op, payload).then((r) => { toast(r.msg || 'Đã xong.'); if (r.user) adm.user = r.user; adm.glog = null; render(); }).catch((err) => toast(err.msg, true));
  }

  function giftForm(id, uid) {
    const items = Object.entries(ITEMS).filter(([, it]) => it.slot !== 'material' || it.price);
    return `<form id="${id}" class="gift-form" ${uid ? `data-uid="${uid}"` : ''}>
      <input type="text" name="subject" maxlength="80" placeholder="Tiêu đề thư" required>
      <input type="text" name="body" maxlength="300" placeholder="Lời nhắn (không bắt buộc)">
      <div class="btn-row"><label class="small">Vàng <input type="number" name="gold" min="0" value="0"></label>
        <label class="small">EXP <input type="number" name="xp" min="0" value="0"></label></div>
      <div class="btn-row"><select name="item"><option value="">(không kèm đồ)</option>${items.map(([k, it]) => `<option value="${k}">${esc(it.name)}</option>`).join('')}</select>
        <input type="number" name="n" min="1" value="1" aria-label="Số lượng"></div>
      <div class="btn-row"><select name="gbase"><option value="">(không kèm trang bị)</option>${Object.entries(ITEMS).filter(([, it]) => ['weapon', 'armor', 'shield', 'wing'].includes(it.slot)).map(([k, it]) => `<option value="${k}">${esc(it.name)}</option>`).join('')}</select>
        <select name="grar" aria-label="Loại đồ"><option value="0">Đồ thường</option><option value="1">Hiếm: Tốt</option><option value="2">Hiếm: Hiếm</option><option value="3">Hiếm: Sử Thi</option></select>
        <label class="small">+ <input type="number" name="gup" min="0" max="11" value="0"></label>
        <label class="small">× <input type="number" name="gn" min="1" max="10" value="1"></label></div>
      <p class="small muted">Đồ hiếm (chỉ vũ khí, giáp, khiên) có chỉ số theo cấp người nhận.</p>
      <button class="btn primary" type="submit">${icon('envelope')} Gửi quà</button>
    </form>`;
  }

  function onGift(form) {
    const f = new FormData(form);
    const payload = { subject: f.get('subject'), body: f.get('body'), gold: +f.get('gold') || 0, xp: +f.get('xp') || 0, items: {} };
    if (f.get('item')) payload.items[f.get('item')] = Math.max(1, +f.get('n') || 1);
    if (f.get('gbase')) payload.items[`gear:${f.get('gbase')}:${+f.get('grar') || 0}:${+f.get('gup') || 0}`] = Math.max(1, +f.get('gn') || 1);
    if (form.id === 'adm-gift') payload.uid = +form.dataset.uid; else payload.all = true;
    Net.admin('gift', payload).then((r) => { toast(`Đã gửi ${r.sent} thư.`); form.reset(); }).catch((err) => toast(err.msg, true));
  }

  async function onAdmin(t) {
    const d = t.dataset, op = d.adm;
    if (op === 'reload') { adm.reports = null; render(); return loadReports(); }
    if (op === 'online-lookup') {
      try { adm.user = (await Net.admin('lookup', { name: d.name })).user; render(); } catch (e) { toast(e.msg, true); }
      return;
    }
    const payload = {};
    if (d.id) payload.id = +d.id;
    if (d.uid) payload.uid = +d.uid;
    if (d.action) payload.action = d.action;
    if (d.minutes) payload.minutes = +d.minutes;
    if (d.days) payload.days = +d.days;
    try {
      const r = await Net.admin(op, payload);
      if (op === 'audit') { adm.audit = r.audit; return render(); }
      if (op === 'online') { adm.online = r.online; return render(); }
      if (op === 'gold_log') { adm.glog = { uid: payload.uid, log: r.log }; return render(); }
      if (op === 'admin_log') { adm.alog = { uid: payload.uid, log: r.log }; return render(); }
      toast(r.msg || 'Đã xong.');
      if (r.user) adm.user = r.user;
      if (op === 'resolve') adm.reports = adm.reports.filter((r) => r.id !== payload.id);
      if (adm.user && payload.uid === adm.user.id) adm.user = (await Net.admin('lookup', { name: adm.user.username })).user;
      render();
    } catch (e) { toast(e.msg, true); }
  }

  // ---------- Giao dịch trực tiếp ----------
  function pkNote(v) {
    const foe = v.a.uid === Net.userId ? v.b.name : v.a.name;
    if (v.winner == null) note(`Cược đấu với ${foe}: hòa.`, 'info');
    else if (v.winner === Net.userId) note(`Cược đấu thắng ${foe}: +${fmt(v.wager)} vàng.`, 'good');
    else note(`Cược đấu thua ${foe}: −${fmt(v.wager)} vàng.`, 'bad');
  }

  // Đồ sát: không cần đồng ý; server mở trận cho cả hai, client nhận nhân vật mới qua sự kiện "player".
  function slayRow(o) {
    const safe = RULES.slay.safe.includes(P.pos.map);
    const why = safe ? 'Vùng an toàn' : P.level < RULES.slay.minLevel ? `Cần cấp ${RULES.slay.minLevel}` : o.level < RULES.slay.minLevel ? `Dưới cấp ${RULES.slay.minLevel}` : '';
    return `<div class="btn-row"><button class="btn danger" data-act="slay" data-uid="${o.id}" ${why ? 'disabled' : ''}>🗡 Đồ sát</button>${why ? `<span class="small muted">${why}</span>` : ''}</div>`;
  }

  async function slay(uid) {
    try {
      await Net.slay(uid);
      profileUi = { open: false, info: null };
      dialog = null; npc = null; tab = 'map';
    } catch (e) { toast(e.msg, true); }
    render();
  }

  async function pkOp(op, payload) {
    try {
      const r = await Net.pk(op, payload);
      pk = r;
      if (op === 'invite') { toast(`Đã mời cược ${fmt(payload.wager)} vàng. Chờ người kia nhận…`); profileUi = { open: false, info: null }; tab = 'map'; }
      if (dialog && dialog.type === 'pk') dialog = null;
      if (r.result) { dialog = { type: 'pkResult', view: r.result }; Sound.play('rare'); pkNote(r.result); }
      else if (op !== 'invite' && dialog && dialog.type === 'player') dialog = null;
    } catch (e) {
      toast(e.msg, true);
      if (dialog && dialog.type === 'pk') dialog = null;
    }
    render();
  }

  async function tradeOp(op, payload) {
    try {
      const r = await Net.trade(op, payload);
      trade = r.trade;
      if (op === 'request') toast('Đã gửi lời mời giao dịch.');
    } catch (e) { toast(e.msg, true); }
    if (dialog && dialog.type === 'trade') dialog = null;
    render();
  }
  // gửi lại toàn bộ món mình đưa ra sau khi sửa
  function tradeOffer(change) {
    const m = trade.mine;
    const offer = { items: Object.assign({}, m.items), gear: m.gear.map((g) => g.uid), gold: m.gold };
    change(offer);
    tradeOp('offer', { offer });
  }
  function tradeLines(o, mine) {
    const rm = (kind, id) => (mine && trade.status === 'open' ? `<button class="btn small-btn" data-act="trade-rm" data-kind="${kind}" data-id="${id}" aria-label="Bỏ ra">✕</button>` : '');
    const rows = Object.entries(o.items).map(([id, n]) => { const it = ITEMS[id]; return `<div class="item">${itemIcon(it)}<div class="grow"><div class="name">${esc(it.name)} <span class="muted num">×${n}</span></div></div>${rm('item', id)}</div>`; })
      .concat(o.gear.map((g) => `<div class="item">${itemIcon(ITEMS[g.base] || { icon: 'sword' }, g.rarity, g.up)}<div class="grow"><div class="name"><span class="rar-${g.rarity}">${esc(g.name)}</span>${g.up ? ` <span class="up-lv">+${g.up}</span>` : ''}</div><div class="small muted">${RARITY[g.rarity] || ''}</div></div>${rm('gear', g.uid)}</div>`));
    if (o.gold) rows.push(`<div class="item">${icon('two-coins', 'lg')}<div class="grow"><div class="name num" style="color:var(--gold)">${fmt(o.gold)} vàng</div></div>${rm('gold', '')}</div>`);
    return rows.length ? `<div class="list">${rows.join('')}</div>` : '<p class="small muted">Chưa bỏ gì vào.</p>';
  }
  function viewTrade() {
    const t = trade, busy = t.status === 'executing';
    const ready = (on) => (on ? '<span class="tag good">✔ Đã xác nhận</span>' : '<span class="tag">Chưa xác nhận</span>');
    const used = new Set(t.mine.gear.map((g) => g.uid));
    const items = Object.keys(P.inv).filter((id) => P.inv[id] - (t.mine.items[id] || 0) > 0).concat(bagGear().filter((id) => !used.has(id) && !itemOf(id).locked));
    const add = t.status === 'open' ? `<form id="trade-add" class="gift-form">
        ${items.length ? `<select name="item">${items.map((id) => { const it = itemOf(id); return `<option value="${id}">${esc(it.name)}${isGear(id) ? gearTag(id) : ` · còn ${P.inv[id] - (t.mine.items[id] || 0)}`}</option>`; }).join('')}</select>
        <div class="btn-row"><label class="small">Số lượng <input type="number" name="count" min="1" value="1"></label><button class="btn" type="submit">Bỏ vào</button></div>` : ''}
        <div class="btn-row"><label class="small">Vàng <input type="number" name="gold" min="0" max="${P.gold}" value="${t.mine.gold || ''}" placeholder="0"></label><button class="btn" type="submit" name="set" value="gold">Đặt vàng</button></div>
      </form>` : '';
    return `<div class="row"><h2 class="display grow">🤝 Giao dịch với ${esc(t.partner_name)}</h2><button class="btn" data-act="trade-op" data-op="cancel" ${busy ? 'disabled' : ''}>Hủy</button></div>
      <div class="card"><div class="row"><h3 class="grow">Bạn đưa</h3>${ready(t.my_ready)}</div>${tradeLines(t.mine, true)}${add}</div>
      <div class="card"><div class="row"><h3 class="grow">${esc(t.partner_name)} đưa</h3>${ready(t.their_ready)}</div>${tradeLines(t.theirs, false)}</div>
      <p class="small muted">Đổi món của bên nào thì cả hai phải xác nhận lại. Cả hai cùng xác nhận thì đổi ngay.</p>
      <button class="btn primary block" data-act="trade-op" data-op="ready" ${t.my_ready || busy ? 'disabled' : ''}>${busy ? 'Đang đổi…' : t.my_ready ? `Đợi ${esc(t.partner_name)} xác nhận…` : '✔ Xác nhận đổi'}</button>`;
  }

  // ---------- Thăm nhà người khác ----------
  async function openVisit(uid) {
    visit = { uid, info: null };
    dialog = null;
    render();
    try { visit.info = await Net.visit(uid); } catch (e) { toast(e.msg, true); visit = null; }
    render();
  }
  function viewVisit() {
    const v = visit.info;
    const head = `<div class="row"><h2 class="display grow">🏡 ${v ? `Nhà của ${esc(v.name)}` : 'Đang ghé…'}</h2><button class="btn" data-act="visit-close">Về</button></div>`;
    if (!v) return head;
    return `${head}
      <div class="card"><div class="map-wrap"><canvas id="visit-canvas" aria-label="Nhà của ${esc(v.name)}"></canvas></div>
        <div class="row" style="margin-top:8px"><div class="grow small">
          <div>Tiện nghi <b>${v.comfort}</b> · ${v.decor.length} món trang trí</div>
          <div class="muted">❤ ${fmt(v.likes)} lượt khen</div></div>
          ${v.id === Net.userId ? '<span class="small muted">Nhà của bạn</span>'
            : v.liked ? '<span class="tag good">Đã khen</span>'
            : `<button class="btn primary" data-act="home-like" data-uid="${v.id}">❤ Khen nhà</button>`}
        </div></div>`;
  }

  // Bảng nổi trên bản đồ: hỏi đấu trùm, chọn nơi dịch chuyển.
  function viewDialog() {
    if (!dialog) return '';
    if (dialog.type === 'invite') {
      return `<div class="map-dialog card">
        <h3>Mời vào tổ đội</h3><p class="small">${esc(dialog.name || 'Một người chơi')} mời bạn vào tổ đội. Đánh chung một con quái thì cùng thắng, chia thưởng.</p>
        <div class="btn-row"><button class="btn" data-act="party-decline">Từ chối</button><button class="btn primary" data-act="party-accept">Vào tổ đội</button></div>
      </div>`;
    }
    if (dialog.type === 'pk') {
      const v = dialog.inv;
      return `<div class="map-dialog card">
        <h3>⚔ Lời mời cược đấu</h3>
        <p class="small"><b>${esc(v.name)}</b> (${CLASSES[v.cls] ? CLASSES[v.cls].name : ''} · cấp ${v.level}) mời bạn cược <b style="color:var(--gold)">${fmt(v.wager)} vàng</b>.</p>
        <p class="small muted">Bản sao chỉ số của hai người tự đánh nhau ngay. Thắng nhận ${fmt(v.wager)} vàng của đối thủ, thua mất ${fmt(v.wager)} vàng, hòa không ai mất gì. Lời mời hết hạn sau ${RULES.pkInvite} giây.</p>
        <div class="btn-row"><button class="btn" data-act="pk-op" data-op="decline">Từ chối</button><button class="btn primary" data-act="pk-op" data-op="accept">${icon('crossed-swords')} Nhận cược</button></div>
      </div>`;
    }
    if (dialog.type === 'pkResult') {
      const v = dialog.view, me = Net.userId;
      const out = v.winner == null ? 'Hòa' : v.winner === me ? `Thắng +${fmt(v.wager)} vàng` : `Thua −${fmt(v.wager)} vàng`;
      return `<div class="map-dialog card" id="pk-result">
        <h3>⚔ ${esc(v.a.name)} đấu ${esc(v.b.name)}</h3>
        <p><b style="color:var(${v.winner == null ? '--parch' : v.winner === me ? '--good' : '--bad'})">${out}</b> <span class="small muted">· ${v.rounds} lượt · cược ${fmt(v.wager)}</span></p>
        <div class="log" style="height:220px">${v.log.map((l) => `<div class="${l.kind === 'hurt' ? 'bad' : l.kind}">${esc(l.text)}</div>`).join('')}</div>
        <div class="btn-row"><button class="btn primary" data-act="dialog-close">Đóng</button></div>
      </div>`;
    }
    if (dialog.type === 'trade') {
      return `<div class="map-dialog card">
        <h3>Lời mời giao dịch</h3><p class="small">${esc(dialog.name || 'Một người chơi')} muốn đổi đồ với bạn.</p>
        <div class="btn-row"><button class="btn" data-act="trade-op" data-op="decline">Từ chối</button><button class="btn primary" data-act="trade-op" data-op="accept">🤝 Xem</button></div>
      </div>`;
    }
    if (dialog.type === 'player') {
      const o = dialog.info;
      if (!o) return `<div class="map-dialog card"><p class="small muted">Đang xem…</p></div>`;
      const inParty = party && party.members.some((m) => m.id === o.id);
      const canInvite = !inParty && (!party || party.leader === Net.userId) && (!party || party.members.length < party.max);
      return `<div class="map-dialog card">
        <div class="row"><img class="sprite" src="${window.Doll.url(o.look)}" alt=""><div class="grow">
          ${o.title ? `<span class="title-tag">${esc(o.title)}</span>` : ''}<h3>${o.guild ? `<span class="guild-tag">[${esc(o.guild.tag)}]</span> ` : ''}${esc(o.name)}</h3>
          <p class="small muted">${CLASSES[o.cls] ? CLASSES[o.cls].name : ''} · ${o.rebirths ? `CS${o.rebirths} · ` : ''}Cấp ${o.level} · Đấu trường ${o.arena.rating} (${o.arena.wins}T/${o.arena.losses}B)</p></div></div>
        <p class="small">${[o.gear.weapon, o.gear.armor, o.gear.shield, o.gear.wing].filter(Boolean).map(esc).join(' · ')}</p>
        <div class="btn-row">
          ${canInvite ? `<button class="btn" data-act="party-invite" data-uid="${o.id}">Mời tổ đội</button>` : ''}
          <button class="btn" data-act="home-visit" data-uid="${o.id}">🏡 Thăm nhà</button>
          <button class="btn" data-act="trade-op" data-op="request" data-uid="${o.id}">🤝 Giao dịch</button>
          <button class="btn" data-act="friend-op" data-op="request" data-uid="${o.id}">👥 Kết bạn</button>
          <button class="btn primary" data-act="pvp_challenge" data-uid="${o.id}">${icon('crossed-swords')} Thách đấu</button>
        </div>
        ${slayRow(o)}
        <div class="btn-row"><button class="btn small-btn" data-act="${o.blocked ? 'unblock' : 'chat-block'}" data-uid="${o.id}">${o.blocked ? 'Bỏ chặn chat' : 'Chặn chat'}</button><button class="btn small-btn" data-act="dialog-close">Đóng</button></div>
      </div>`;
    }
    if (dialog.type === 'boss') {
      const b = dialog.boss, weak = P.level < b.level - 1;
      return `<div class="map-dialog card">
        <div class="row">${sprite(b.id, '', b.name)}<div class="grow"><h3>Đấu ${esc(b.name)}?</h3><p class="small muted">Trùm cấp ${b.level}.${weak ? ` <span style="color:var(--bad)">Bạn mới cấp ${P.level}, nên luyện thêm.</span>` : ''}</p></div></div>
        <div class="btn-row"><button class="btn" data-act="dialog-close">Thôi</button><button class="btn primary" data-act="boss-yes">${icon('crowned-skull')} Đấu</button></div>
      </div>`;
    }
    const W = window.GAME_DATA.WORLD.maps;
    const places = ['village'].concat(P.waystones || []);
    return `<div class="map-dialog card">
      <h3>Đá dịch chuyển</h3>
      <p class="small muted">Chạm vào đá ở nơi khác để ghi nhớ nó.</p>
      <div class="list">${places.map((id) => `<button class="btn" data-act="teleport" data-to="${id}" ${id === P.pos.map ? 'disabled' : ''}>${esc(W[id].name)}${id === P.pos.map ? ' · đang ở đây' : ''}</button>`).join('')}</div>
      <button class="btn" data-act="dialog-close">Đóng</button>
    </div>`;
  }

  // ---------- Câu cá ----------
  function nearWater() {
    const m = WORLD.maps[P.pos.map];
    if (!m) return false;
    return [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => (m.tiles[P.pos.y + dy] || '')[P.pos.x + dx] === '~');
  }

  function viewFishing() {
    if (fishing) {
      const bite = fishing.phase === 'bite';
      return `<div id="fish-ui" class="fish-ui ${bite ? 'bite' : ''}">
        <span class="bobber ${bite ? 'sink' : ''}" aria-hidden="true"></span>
        <b>${bite ? 'Cá cắn câu! Giật ngay!' : 'Đang chờ cá cắn câu…'}</b>
        <button class="btn ${bite ? 'primary' : ''}" data-act="fish-reel">${icon('fishing-pole')} Giật cần</button>
      </div>`;
    }
    if (dialog || P.pos.map === 'tower' || !nearWater()) return '<div id="fish-ui" hidden></div>';
    return `<div id="fish-ui" class="fish-ui idle"><button class="btn" data-act="fish-cast">${icon('fishing-pole')} Câu cá</button></div>`;
  }

  function stopFishing() {
    if (!fishing) return;
    fishing.timers.forEach(clearTimeout);
    fishing = null;
  }

  function redrawFishing() {
    const el = $('#fish-ui');
    if (el) el.outerHTML = viewFishing();
  }

  async function castLine() {
    if (busy || fishing) return;
    busy = true;
    const t0 = performance.now();
    try {
      const r = await Net.send({ act: 'fish_cast' });
      P = r.player;
      if (!r.ok) { toast(r.msg, true); busy = false; return; }
      const rtt = performance.now() - t0;
      // server tính giờ cá cắn từ lúc nhận lệnh; lệnh giật cũng mất nửa vòng mạng mới tới,
      // nên hiện "cá cắn" sớm hơn một vòng mạng để bấm kịp
      const biteIn = Math.max(0, r.wait - rtt);
      const f = { phase: 'wait', timers: [] };
      fishing = f;
      f.timers.push(setTimeout(() => { if (fishing !== f) return; f.phase = 'bite'; Sound.play('bite'); if (navigator.vibrate) navigator.vibrate(120); redrawFishing(); }, biteIn));
      f.timers.push(setTimeout(() => { if (fishing !== f) return; stopFishing(); toast('Chậm tay rồi, cá ăn mất mồi.', true); redrawFishing(); }, biteIn + r.window + 400));
      Sound.play('cast');
    } catch (e) { toast(e.msg, true); }
    busy = false;
    redrawFishing();
  }

  async function reelIn() {
    if (!fishing || busy) return;
    stopFishing();
    busy = true;
    try {
      const r = await Net.send({ act: 'fish_reel' });
      P = r.player;
      result(r);
      Sound.play(!r.ok ? 'error' : r.fish === 'fish_gold' ? 'rare' : 'catch');
    } catch (e) { toast(e.msg, true); }
    busy = false;
    refresh();
  }

  // ---------- Hướng dẫn người mới ----------
  function viewTutorial() {
    const t = P.view.tutorial;
    if (!t) return '<div id="tut" hidden></div>';
    return `<div class="card tut" id="tut">
      <div class="row"><span class="tag gold num">Hướng dẫn ${t.step}/${t.total}</span><b class="grow">${esc(t.text)}</b>
        <button class="btn small-btn" data-act="tutorial_skip" aria-label="Tắt hướng dẫn">Bỏ qua</button></div>
      <p class="small muted">${esc(t.hint)}${t.target ? ' Làm theo vòng sáng trên bản đồ.' : ''}</p>
    </div>`;
  }

  // ---------- Trùm thế giới ----------
  const clock = (ms) => { const t = Math.max(0, Math.round(ms / 1000)); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`; };

  // ---------- Golden Invasion (Phase 7) ----------
  let invasion = null; // { active, ends_at, maps: { id: 'run' | 'boss' | 'done' } }
  function onInvasion(st) {
    const was = invasion && invasion.active;
    invasion = st;
    if (st.active && !was) { toast('✨ Golden Invasion! Quái vàng xuất hiện.'); note('Golden Invasion bắt đầu: quái vàng thưởng ×5.', 'good'); Sound.play('rare'); }
  }

  function viewBossBanner() {
    if (!wb.alive) return '';
    const pct = Math.max(0, Math.round((wb.hp / wb.maxHp) * 100));
    const here = P.pos.map === 'altar';
    return `<div class="card wb" id="wb">
      <div class="row">${sprite('ancient_dragon', '', wb.name)}<div class="grow">
        <b>${esc(wb.name)}</b> <span class="small muted">${here ? 'ngay trước mặt' : 'ở Tế Đàn (cổng dưới bên trái Làng)'}</span>
        ${bar('boss', wb.hp, wb.maxHp, `${pct}% · còn <span id="wb-left">${clock(wb.endsAt - wb.skew - Date.now())}</span> · ${wb.fighters} người đánh`)}
      </div></div>
      ${here && wb.top.length ? `<ol class="board">${wb.top.map((t, i) => `<li class="${t.id === Net.userId ? 'me' : ''}"><span class="num rank">${i + 1}</span><span class="grow">${esc(t.name)}</span><span class="num">${fmt(t.dmg)}</span></li>`).join('')}</ol>` : ''}
    </div>`;
  }

  function onWorldBoss(st) {
    const wasAlive = wb.alive;
    wb = Object.assign(st, { skew: st.now - Date.now() });
    Map_.setBoss(wb);
    // đang đánh trùm: thanh máu theo máu chung
    if (P && P.battle && P.battle.monster.world && !P.battle.over && wb.alive) {
      P.battle.monster.hp = wb.hp;
      render();
      return;
    }
    if (!P || P.battle) return;
    if (tab === 'map' && !npc) {
      const el = $('#wb');
      if (el && wb.alive) el.outerHTML = viewBossBanner();
      else if (el || wb.alive !== wasAlive) render();
    }
  }

  // ---------- Chat ----------
  const mapName = (id) => (WORLD.maps[id] ? WORLD.maps[id].name : id);

  // V2: khi khung chat đóng, mỗi tin hiện 5 giây kể từ lúc tới rồi mờ đi (tin cũ / lịch sử không hiện)
  const CHAT_SHOW_MS = 5000;
  function ovLine(m) {
    const d = (m._t || 0) + CHAT_SHOW_MS - Date.now();
    return chatLine(m).replace('<div class="chat-line', `<div style="--d:${Math.max(0, d)}ms" class="chat-line${d <= 0 ? ' gone' : ''}`);
  }
  function chatLine(m) {
    if (!m.uid) return `<div class="chat-line system ${m.guild ? 'guild' : ''}">${m.guild ? '[Bang] ' : ''}${esc(m.text)}</div>`;
    const mine = m.uid === Net.userId;
    const title = (m.guild ? '<span class="guild-mark">[Bang]</span> ' : '') + (m.party ? '<span class="party-mark">[Đội]</span> ' : '') + (m.tag ? `<span class="guild-tag">[${esc(m.tag)}]</span> ` : '') + (m.title ? `<span class="title-tag">${esc(m.title)}</span> ` : '');
    const name = title + (mine || m.id == null ? `<b>${esc(m.name)}</b>` : `<button class="chat-name" data-chat="${m.id}">${esc(m.name)}</button>`);
    const menu = m.id != null && chatMenu === m.id
      ? `<div class="chat-menu"><button class="btn small-btn" data-act="chat-report" data-id="${m.id}">Báo cáo tin này</button><button class="btn small-btn" data-act="chat-block" data-uid="${m.uid}">Chặn ${esc(m.name)}</button></div>` : '';
    return `<div class="chat-line ${mine ? 'mine' : ''} ${m.guild ? 'guild' : ''} ${m.party ? 'party' : ''}">${name} ${m.guild || m.party ? '' : `<span class="muted small">${esc(mapName(m.map))}</span> `}${esc(m.text)}${menu}</div>`;
  }

  // kênh chat đang có: thế giới, bang (nếu có bang), tổ đội (nếu có tổ đội)
  const chatChannels = () => ['world'].concat(P && P.guild ? ['guild'] : [], party ? ['party'] : []);

  // ---------- Tổ đội ----------
  function viewParty() {
    if (!party) return '<div id="party-card" hidden></div>';
    const lead = party.leader === Net.userId;
    return `<div class="card party" id="party-card">
      <div class="row"><b class="grow">Tổ đội (${party.members.length}/${party.max})</b><button class="btn small-btn" data-act="party-leave">Rời tổ đội</button></div>
      ${party.members.map((m) => `<div class="party-member"><span class="grow">${m.id === party.leader ? '★ ' : ''}${esc(m.name)} <span class="small muted">Cấp ${m.level} · ${esc(mapName(m.map))}</span></span>
        ${lead && m.id !== Net.userId ? `<button class="btn small-btn" data-act="party-kick" data-uid="${m.id}">Mời ra</button>` : ''}
        ${bar('hp', m.hp, m.maxHp, `${fmt(m.hp)} / ${fmt(m.maxHp)}`)}</div>`).join('')}
      <p class="small muted">Chạm vào con quái đồng đội đang đánh để vào đánh cùng.</p>
    </div>`;
  }

  async function partyOp(op, payload) {
    try {
      const r = await Net.party(op, payload);
      party = r.party;
      if (op === 'invite') toast('Đã gửi lời mời.');
      if (op === 'accept') toast('Đã vào tổ đội.');
      if (op === 'leave') { toast('Đã rời tổ đội.'); if (chatTo === 'party') chatTo = 'world'; }
    } catch (e) { toast(e.msg, true); }
    dialog = null;
    render();
  }

  // Phase 13: chạm tên trong danh sách 👫 (hoặc "Hồ sơ" ở tab Nhân vật) mở hồ sơ đầy đủ
  async function openPlayer(o) {
    profileUi = { open: true, info: null };
    walk = null;
    render();
    try { profileUi = { open: true, info: await Net.inspect(o.id) }; } catch (e) { toast(e.msg, true); profileUi = { open: false, info: null }; }
    render(); const v = $('#view'); if (v) v.scrollTop = 0;
  }

  // ---------- Người trong bản đồ (Phase 13) ----------
  const others = () => (P && !P.battle ? Map_.players() : []);
  function peopleDot() { const n = others().length; return n ? `<span class="points-dot">${n}</span>` : ''; }
  let peopleCount = -1;
  function refreshPeopleDot() {
    const n = others().length;
    if (n === peopleCount) return;
    peopleCount = n;
    const b = $('#tabs [data-tab="people"] span:last-child');
    if (b) { const d = b.querySelector('.points-dot'); if (d) d.remove(); if (n) b.insertAdjacentHTML('beforeend', `<span class="points-dot">${n}</span>`); }
    if (tab === 'people' && !profileUi.open && !trade) render();
  }
  function viewPeople() {
    const m = WORLD.maps[P.pos.map] || {};
    const list = others().slice().sort((a, b) => b.level - a.level || a.name.localeCompare(b.name));
    const inParty = (id) => party && party.members.some((x) => x.id === id);
    return `<div class="card"><div class="row"><h3 class="grow">Quanh đây · ${esc(m.name || '')}</h3><span class="tag">${list.length} người</span></div>
      ${list.length ? `<div class="list">${list.map((o) => `<button class="item people-row" data-act="profile" data-uid="${o.id}">
        <img class="sprite sm" src="${window.Doll.url(o.look)}" alt="">
        <div class="grow"><div class="name" style="color:${window.HLLogic.nameColor(o, { party: party ? party.members.map((x) => x.id) : [], tag: P.guild && P.guild.tag, enemy: P.guild && P.guild.war && P.guild.war.enemy && P.guild.war.enemy.tag })}">${o.tag ? `[${esc(o.tag)}] ` : ''}${esc(o.name)}${inParty(o.id) ? ' <span class="small">· Đội</span>' : ''}</div>
          <div class="small muted">${CLASSES[o.cls] ? CLASSES[o.cls].name : ''} · Cấp ${o.level} · ô (${o.x}, ${o.y})</div></div>
        <span class="small muted">›</span></button>`).join('')}</div>` : '<p class="small muted">Chỉ có bạn ở bản đồ này.</p>'}
      <p class="small muted">Người chơi khác không vẽ trên bản đồ; chạm tên để xem hồ sơ, giao dịch, kết bạn, thách đấu…</p></div>`;
  }

  // ---------- Hồ sơ (Phase 13, theo mẫu anh gửi) ----------
  function viewProfile() {
    const o = profileUi.info;
    const head = `<div class="row menu-head"><button class="btn" data-act="profile-close">‹ Quay lại</button><span class="grow"></span></div>`;
    if (!o) return head + '<div class="card"><p class="small muted">Đang tải hồ sơ…</p></div>';
    const pr = o.profile, c = CLASSES[o.cls] || {};
    const kv = (k, v) => `<div class="kv"><span>${k}</span><span class="num">${v}</span></div>`;
    const plus = (v) => (v ? ` <span class="up">+${Math.round(v * 100)}%</span>` : '');
    const stat = (k, n) => { const s = pr.stats[k]; return kv(n, `<b>${fmt(s.base + s.gear)}</b> <span class="muted">(${fmt(s.base)})</span>${s.gear ? ` <span class="up">+${fmt(s.gear)}</span>` : ''}`); };
    const day = (t) => (t ? new Date(t).toLocaleString('vi-VN') : '—');
    const xpPct = pr.xp_need ? Math.floor((pr.xp / pr.xp_need) * 1000) / 10 : 100;
    const inParty = party && party.members.some((m) => m.id === o.id);
    const canInvite = !inParty && (!party || party.leader === Net.userId) && (!party || party.members.length < party.max);
    const actions = o.me ? '' : `<div class="card"><h3>Hành động</h3><div class="btn-row">
        ${canInvite ? `<button class="btn" data-act="party-invite" data-uid="${o.id}">Mời tổ đội</button>` : ''}
        <button class="btn" data-act="home-visit" data-uid="${o.id}">🏡 Thăm nhà</button>
        <button class="btn" data-act="trade-op" data-op="request" data-uid="${o.id}">🤝 Giao dịch</button>
        <button class="btn" data-act="friend-op" data-op="request" data-uid="${o.id}">👥 Kết bạn</button>
        <button class="btn primary" data-act="pvp_challenge" data-uid="${o.id}">${icon('crossed-swords')} Thách đấu</button></div>
      ${slayRow(o)}
      <div class="btn-row"><button class="btn small-btn" data-act="${o.blocked ? 'unblock' : 'chat-block'}" data-uid="${o.id}">${o.blocked ? 'Bỏ chặn chat' : 'Chặn chat'}</button></div></div>`;
    return `${head}
      <div class="card prof-head">
        ${o.title ? `<span class="title-tag">${esc(o.title)}</span>` : ''}
        <h2 class="display" ${pr.red_s ? 'style="color:#ff3b3b"' : ''}>${o.guild ? `<span class="guild-tag">[${esc(o.guild.tag)}]</span> ` : ''}${esc(o.name)}</h2>
        ${pr.red_s ? `<div class="small" style="color:#ff3b3b">🔴 Tên đỏ (đồ sát) · còn ${Math.ceil(pr.red_s / 60)} phút · gục mất vàng gấp ${RULES.slay.redMult} lần</div>` : ''}
        ${pr.protect_s ? `<div class="small" style="color:var(--good)">🛡 Được bảo vệ sau khi gục · còn ${pr.protect_s} giây</div>` : ''}
        ${o.guild ? `<div class="small muted">Bang ${esc(o.guild.name)}</div>` : ''}
        <div class="prof-lv">${o.rebirths ? `CS${o.rebirths} · ` : ''}Cấp ${o.level} ${esc(c.name || '')}</div>
        <img class="sprite prof-doll" src="${window.Doll.url(o.look)}" alt="">
        <div class="small muted">${pr.online ? `🟢 Đang online${pr.where ? ` @ ${esc(pr.where)}` : ''}` : `Lần cuối: ${day(pr.last_seen)}`}</div>
      </div>
      <div class="prof-boxes">
        <div class="prof-box">Hạng: <b>#${pr.rank || '—'}</b></div>
        <div class="prof-box">${esc(c.name || '')}: <b>#${pr.class_rank || '—'}</b></div>
        <div class="prof-box">Đấu trường <span class="muted">${pr.arena.rating}</span><br>🏆 ${pr.arena.wins}T / ${pr.arena.losses}B</div>
      </div>
      <div class="card">${bar('hp', pr.hp, pr.max_hp, `❤ ${fmt(pr.hp)} / ${fmt(pr.max_hp)}`)}${bar('mp', pr.mp, pr.max_mp, `💧 ${fmt(pr.mp)} / ${fmt(pr.max_mp)}`)}</div>
      <div class="card">
        ${stat('str', 'Sức mạnh')}${stat('agi', 'Nhanh nhẹn')}${stat('vit', 'Thể lực')}${stat('ene', 'Năng lượng')}
        <hr class="sep">
        ${kv('Sát thương', `<b>${fmt(pr.atk_min)} ~ ${fmt(pr.atk_max)}</b>${plus(pr.pct.atk)}`)}
        ${kv('Phòng thủ', `<b>${fmt(pr.def)}</b>${plus(pr.pct.def)}`)}
        ${kv('Máu tối đa', `<b>${fmt(pr.max_hp)}</b>${plus(pr.pct.hp)}`)}
        ${kv('Chí mạng · Né', `${Math.round(pr.crit * 100)}% · ${Math.round(pr.dodge * 100)}%`)}
        ${pr.pct.wing_dmg ? kv('Cánh', `+${Math.round(pr.pct.wing_dmg * 100)}% sát thương · −${Math.round(pr.pct.wing_absorb * 100)}% nhận`) : ''}
      </div>
      <div class="card">
        ${kv(`${icon('two-coins')} Vàng`, fmt(pr.gold))}
        ${kv('⭐ Kinh nghiệm', `${fmt(pr.xp)} / ${fmt(pr.xp_need)} (${xpPct}%)`)}
        ${bar('xp', pr.xp, pr.xp_need, '')}
      </div>
      <div class="card"><h3>Trang bị</h3>
        ${pr.equip.length ? `<div class="prof-gear">${pr.equip.map((g) => `<div class="prof-item">${itemIcon(ITEMS[g.id] || { icon: 'sword' }, g.rarity, g.up)}<span class="rar-${g.rarity}">${esc(g.name)}</span>${g.up ? ` <span class="up-lv">+${g.up}</span>` : ''}</div>`).join('')}</div>` : '<p class="small muted">Chưa mặc gì.</p>'}
      </div>
      <div class="card">
        ${kv('🐾 Thú cưng', pr.pet ? `${esc(pr.pet)} <span class="muted">(${pr.pets} con)</span>` : pr.pets ? `${pr.pets} con` : '—')}
        ${kv('🏪 Đang bán ở chợ', `${pr.market} món`)}
      </div>
      <div class="card">
        ${kv('Nhiệm vụ đã xong', fmt(pr.counts.quests))}
        ${kv('Quái đã hạ', fmt(pr.counts.kills))}
        ${kv('Trùm đã hạ', fmt(pr.counts.bosses))}
        ${kv('Tháp cao nhất', `Tầng ${pr.counts.tower}`)}
        ${kv('Đấu trường thắng / thua', `${pr.arena.wins} / ${pr.arena.losses}`)}
        ${kv('PK cược thắng / thua', `${pr.counts.pk_wins} / ${pr.counts.pk_losses}`)}
        ${kv('Gục ngã', fmt(pr.counts.deaths))}
      </div>
      <div class="card small muted">
        ${kv('Lần cuối online', pr.online ? 'Đang online' : day(pr.last_seen))}
        ${kv('Đăng ký', day(pr.registered))}
      </div>
      ${actions}`;
  }

  // ---------- Chợ ----------
  async function loadMarket() {
    if (market.loading) return;
    market.loading = true;
    try { market.data = await Net.market(market.q); } catch (e) { toast(e.msg, true); }
    market.loading = false;
    if (npc) render();
  }

  // món hàng: đồ thường (item, count) hoặc đồ chỉ số ngẫu nhiên (gear)
  function listingRow(l, right, showSeller) {
    const it = l.gear || ITEMS[l.item];
    const name = l.gear ? `<span class="rar-${l.gear.rarity}">${esc(l.name)}</span>${l.gear.up ? ` <span class="up-lv">+${l.gear.up}</span>` : ''}` : esc(l.name);
    const detail = l.gear ? itemStat(l.gear) : it.slot === 'material' ? it.desc : itemStat(it);
    return `<div class="item">${itemIcon(it, l.gear && l.gear.rarity, l.gear && l.gear.up)}<div class="grow">
      <div class="name">${name}${l.count > 1 ? ` <span class="muted num">×${l.count}</span>` : ''}</div>
      <div class="small muted">${detail}${showSeller ? ` · người bán ${esc(l.seller)}` : ''}</div></div>${right}</div>`;
  }

  function viewMarket() {
    if (!market.data) { loadMarket(); return '<div class="card"><p class="small muted">Đang tải chợ…</p></div>'; }
    const d = market.data, mine = d.listings.filter((l) => l.mine), others = d.listings.filter((l) => !l.mine);
    const tabs = `<div class="seg">${[['buy', 'Mua'], ['sell', 'Bán'], ['mine', `Hàng của tôi (${mine.length})`]].map(([k, l]) => `<button class="btn ${market.tab === k ? 'primary' : ''}" data-act="market-tab" data-tab2="${k}">${l}</button>`).join('')}</div>`;
    let body = '';
    if (market.tab === 'buy') {
      body = `<form id="market-search" class="chat-form"><input type="text" id="market-q" placeholder="Tìm theo tên" value="${esc(market.q)}"><button class="btn" type="submit">Tìm</button></form>
        ${others.length ? `<div class="list">${others.map((l) => listingRow(l, `<button class="btn ${P.gold >= l.price ? 'primary' : ''}" data-act="market_buy" data-listing="${l.id}" ${P.gold >= l.price ? '' : 'disabled'}>${icon('two-coins')}${fmt(l.price)}</button>`, true)).join('')}</div>` : '<p class="small muted">Chợ chưa có hàng nào.</p>'}`;
    } else if (market.tab === 'mine') {
      body = mine.length ? `<div class="list">${mine.map((l) => listingRow(l, `<div class="market-mine"><span class="num" style="color:var(--gold)">${fmt(l.price)} vàng</span><button class="btn small-btn" data-act="market_cancel" data-listing="${l.id}">Rút về</button></div>`)).join('')}</div>`
        : '<p class="small muted">Bạn chưa rao bán gì.</p>';
    } else {
      const items = Object.keys(P.inv).filter((id) => P.inv[id] > 0).concat(bagGear().filter((id) => !itemOf(id).locked));
      body = items.length ? `<form id="market-sell" class="gift-form">
          <select name="item">${items.map((id) => { const it = itemOf(id); return `<option value="${id}">${esc(it.name)}${isGear(id) ? gearTag(id) : ` · có ${P.inv[id]}`}</option>`; }).join('')}</select>
          <div class="btn-row"><label class="small">Số lượng <input type="number" name="count" min="1" value="1"></label>
            <label class="small">Giá <input type="number" name="price" min="1" placeholder="vàng" required></label></div>
          <button class="btn primary" type="submit">Rao bán</button>
          <p class="small muted">Bán được thì tiền gửi vào hộp thư, trừ ${d.fee}% phí chợ. Tối đa ${d.max} món cùng lúc. Đồ đang mặc thì tháo ra trước.</p>
        </form>` : '<p class="small muted">Túi trống.</p>';
    }
    return `<div class="card"><div class="row"><h3 class="grow">Chợ</h3><button class="btn small-btn" data-act="market-reload">Tải lại</button></div>${tabs}${body}</div>`;
  }

  // ---------- Đấu trường ----------
  async function loadArena() {
    try { arena = await Net.arena(); pk = await Net.pk('info'); } catch (e) { /* thử lại lần sau */ }
    if (onMenu('arena')) { const el = $('#arena'); if (el) el.outerHTML = viewArena(); }
  }

  function viewArena() {
    if (!arena) return '<div class="card" id="arena"><h3>Đấu trường</h3><p class="small muted">Đang tải…</p></div>';
    const me = arena.me, left = me.per_day - me.today;
    return `<div class="card" id="arena">
      <div class="row">${icon('crossed-swords', 'lg')}<div class="grow"><h3>Đấu trường</h3>
        <p class="small muted">Đánh với bản sao chỉ số của người chơi khác (họ không cần online). Gục ngã tính như chết (mất vàng, về Nhà). Chạm vào người khác trên bản đồ để thách đấu.</p></div>
        <span class="tag gold num">${me.rating}</span></div>
      <p class="small">${me.wins} thắng · ${me.losses} thua · còn ${left} trận hôm nay</p>
      <div class="list">${arena.suggestions.map((o) => `<div class="item"><div class="grow"><div class="name">${esc(o.name)}</div>
        <div class="small muted">${CLASSES[o.cls] ? CLASSES[o.cls].name : ''} · Cấp ${o.level} · điểm ${o.rating}</div></div>
        <button class="btn" data-act="pvp_challenge" data-uid="${o.user_id}" ${left > 0 ? '' : 'disabled'}>Thách đấu</button></div>`).join('') || '<p class="small muted">Chưa có đối thủ nào.</p>'}</div>
      ${pk ? `<h3>🗡 Đồ sát</h3><p class="small muted">Chạm tên người chơi cùng bản đồ (từ cấp ${RULES.slay.minLevel}, ngoài Làng và Nhà) rồi bấm Đồ sát: hai bên vào trận ngay, luân phiên lượt ${RULES.slay.turnS} giây. Thua hoặc bỏ chạy là gục ngã; vàng mất chuyển cho người thắng.</p>
        <div class="list" id="pk-history">${pk.history.map((h) => {
          const mine = h.a_id === Net.userId, foe = mine ? h.b_name : h.a_name;
          const res = h.winner_id == null ? '<span class="tag num">Hòa</span>' : h.winner_id === Net.userId ? `<span class="tag good num">+${fmt(h.wager)}</span>` : `<span class="tag bad num">−${fmt(h.wager)}</span>`;
          return `<div class="item"><div class="grow"><div class="name">${esc(foe)}</div><div class="small muted">${h.rounds} lượt · ${new Date(h.at).toLocaleString('vi-VN')}</div></div>${res}</div>`;
        }).join('') || '<p class="small muted">Chưa có trận nào.</p>'}</div>` : ''}
    </div>`;
  }

  // Chat kiểu MU Web (Phase 9, U4): đè lên góc dưới trái bản đồ, tin cũ mờ dần; ô nhập ẩn tới khi bấm Enter / 💬
  // (nút 💬 ở góc dưới phải, chấm đỏ khi có tin mới lúc ô nhập đang đóng).
  let chatOpen = false, chatUnread = false, chatWide = false;
  const chatBtn = () => `<button class="chat-btn" data-act="chat-open" aria-label="${chatOpen ? 'Đóng chat' : 'Mở chat'}">💬${chatUnread && !chatOpen ? '<span class="chat-dot"></span>' : ''}</button>`;
  function viewChat() {
    return `<div class="chat-ov ${chatOpen || chatWide ? 'open' : ''}" id="chat-ov">
      ${chatOpen ? `<button class="chat-wide" data-act="chat-wide" aria-label="Xem lịch sử chat">${chatWide ? '▾' : '▴'}</button>` : ''}
      <div class="chat-log" id="chat-log" aria-live="polite">${chats.map(ovLine).join('')}</div>
      ${chatOpen ? `<form id="chat-form" class="chat-form" autocomplete="off">
        ${chatChannels().length > 1 ? `<button type="button" class="btn chat-to ${chatTo !== 'world' ? 'on' : ''}" data-act="chat-to" aria-label="Đổi kênh chat">${{ world: 'Tất cả', guild: 'Bang', party: 'Đội' }[chatTo]}</button>` : ''}
        <input type="text" id="chat-input" maxlength="120" placeholder="${{ world: 'Nói với mọi người…', guild: 'Nói trong bang…', party: 'Nói trong tổ đội…' }[chatTo]}" value="${esc(chatDraft)}" aria-label="Tin nhắn">
        <button class="btn" type="submit">Gửi</button>
      </form>` : ''}
    </div>${chatBtn()}`;
  }
  function toggleChat(on) {
    chatOpen = on; if (on) chatUnread = false; else chatWide = false;
    const ov = $('#chat-ov');
    if (ov) { const b = $('.chat-btn'); if (b) b.remove(); ov.outerHTML = viewChat(); const log = $('#chat-log'); if (log) log.scrollTop = log.scrollHeight; }
    if (on) { const ci = $('#chat-input'); if (ci) ci.focus(); }
  }

  function onChatMessage(m) {
    m._t = Date.now();
    chats.push(m);
    if (chats.length > 50) chats.shift();
    // người nói đang ở cùng bản đồ thì hiện bong bóng trên đầu
    if (P && m.map === P.pos.map) Map_.say(m.uid, m.text);
    if (!chatOpen && m.uid !== Net.userId && !chatUnread) { chatUnread = true; const b = $('.chat-btn'); if (b) b.outerHTML = chatBtn(); }
    const log = $('#chat-log');
    if (log) {
      const atBottom = log.scrollHeight - log.scrollTop - log.clientHeight < 30;
      log.innerHTML = chats.map(ovLine).join('');
      if (atBottom || m.uid === Net.userId) log.scrollTop = log.scrollHeight;
    }
  }

  async function onChatSubmit() {
    const input = $('#chat-input');
    const text = input.value.trim();
    if (!text) return;
    // V3: /d xóa chat trên máy mình
    if (text === '/d') { chats = []; const log = $('#chat-log'); if (log) log.innerHTML = ''; input.value = ''; chatDraft = ''; toast('Đã xóa chat.'); return; }
    const c = L.parseChat(text, chatTo, friendsUi.data && friendsUi.data.friends);
    if (c.error) { toast(c.error, true); return; }
    try {
      if (c.to === 'whisper') {
        await Net.dm('send', { uid: c.uid, text: c.text });
        toast(`Đã gửi tin riêng cho ${c.name}.`);
      } else await Net.chat(c.text, c.to === 'world' ? null : c.to);
      input.value = ''; chatDraft = '';
    } catch (err) {
      toast(err.msg, true);
    }
  }

  // ---------- Bảng xếp hạng ----------
  async function loadBoard(force) {
    if (!force && board.data && Date.now() - board.at < 30000) return;
    board.at = Date.now();
    try {
      board.data = await Net.leaderboard();
      if (onMenu('board')) {
        const el = $('#board');
        if (el) el.outerHTML = viewBoard();
      }
    } catch (err) { /* thử lại lần sau */ }
  }

  function viewBoard() {
    const kinds = [['level', 'Cấp cao'], ['kills', 'Săn nhiều'], ['tower', 'Tháp'], ['dragon', 'Diệt rồng'], ['guild', 'Bang'], ['guild_boss', 'Bang diệt Cổ Long'], ['arena', 'Đấu trường']];
    const byClass = board.kind === 'level' && board.cls;
    const rows = board.data ? (byClass ? (board.data.class || {})[board.cls] || [] : board.data[board.kind]) : null;
    const mr = board.data && board.data.me_rank;
    const meTag = mr ? (byClass ? (mr.cls === board.cls ? `Bạn hạng ${mr.class} trong lớp` : '') : `Bạn hạng ${mr.level}`) : board.data && board.data.me ? `Bạn hạng ${board.data.me}` : '';
    const value = (r) => (board.kind === 'level' ? `${r.rebirths ? `CS${r.rebirths} · ` : ''}Cấp ${r.level}` : board.kind === 'kills' ? `${fmt(r.kills)} quái` : board.kind === 'tower' ? `Tầng ${r.tower_best}` : new Date(r.victory_at).toLocaleDateString('vi-VN'));
    return `<div class="card" id="board">
      <div class="row"><h3 class="grow">Bảng xếp hạng</h3>${meTag ? `<span class="tag gold num">${meTag}</span>` : ''}</div>
      <div class="seg">${kinds.map(([k, label]) => `<button class="btn ${board.kind === k ? 'primary' : ''}" data-board="${k}">${label}</button>`).join('')}</div>
      ${board.kind === 'level' ? `<div class="seg" id="board-cls"><button class="btn small-btn ${board.cls ? '' : 'primary'}" data-board-cls="">Tất cả</button>${Object.keys(CLASSES).map((c) => `<button class="btn small-btn ${board.cls === c ? 'primary' : ''}" data-board-cls="${c}">${CLASSES[c].name}</button>`).join('')}</div>` : ''}
      ${rows == null ? '<p class="small muted">Đang tải…</p>'
        : rows.length === 0 ? `<p class="small muted">${board.kind === 'arena' ? 'Chưa ai đấu. Chạm vào người khác trên bản đồ để thách đấu.' : board.kind === 'guild' ? 'Chưa có bang nào. Lập bang ở thẻ Bang hội.' : board.kind === 'guild_boss' ? 'Chưa bang nào đánh trùm thế giới. Cổ Long xuất hiện ở Tế Đàn.' : board.kind === 'dragon' ? 'Chưa ai hạ được Hắc Long. Bạn sẽ là người đầu tiên?' : board.kind === 'tower' ? 'Chưa ai leo Tháp Vô Tận. Gặp Người Gác Tháp ở Làng.' : 'Chưa có ai.'}</p>`
        : board.kind === 'arena' ? `<ol class="board">${rows.map((r) => `<li class="${r.user_id === Net.userId ? 'me' : ''}"><span class="num rank">${r.rank}</span><span class="grow">${esc(r.name)} <span class="small muted">${r.wins}T/${r.losses}B</span></span><span class="num">${r.rating}</span></li>`).join('')}</ol>`
        : board.kind === 'guild_boss' ? `<ol class="board">${rows.map((g) => `<li class="${P.guild && P.guild.id === g.id ? 'me' : ''}"><span class="num rank">${g.rank}</span><span class="grow"><span class="guild-tag">[${esc(g.tag)}]</span> ${esc(g.name)} <span class="small muted">${g.members} người</span></span><span class="num">${fmt(g.boss_damage)}</span></li>`).join('')}</ol>`
        : board.kind === 'guild' ? `<ol class="board">${rows.map((g) => `<li class="${P.guild && P.guild.id === g.id ? 'me' : ''}"><span class="num rank">${g.rank}</span><span class="grow"><span class="guild-tag">[${esc(g.tag)}]</span> ${esc(g.name)} <span class="small muted">${g.members} người</span></span><span class="num">Cấp ${g.level}</span></li>`).join('')}</ol>`
        : `<ol class="board">${rows.map((r) => `<li class="${r.user_id === Net.userId ? 'me' : ''}"><span class="num rank">${r.rank}</span><span class="grow">${r.title ? `<span class="title-tag">${esc(r.title)}</span> ` : ''}${esc(r.name)} <span class="small muted">${CLASSES[r.cls] ? CLASSES[r.cls].name : ''}</span></span><span class="num">${value(r)}</span></li>`).join('')}</ol>`}
    </div>`;
  }

  // Cập nhật nhẹ khi đang xem bản đồ (không dựng lại cả trang, tránh nháy).
  function refresh() {
    Sound.music(musicMood());
    if (P && !P.battle && tab === 'map' && !npc && Map_.mountedMap() === P.pos.map && $('#map-canvas')) {
      $('#hud').innerHTML = viewHud();
      const head = $('.map-top');
      if (head) head.outerHTML = Map_.top(P);
      const tut = $('#tut');
      if (tut) tut.outerHTML = viewTutorial();
      const fish = $('#fish-ui');
      if (fish) fish.outerHTML = viewFishing();
      Map_.draw();
    } else {
      render();
    }
  }

  function bar(kind, cur, max, label) {
    const w = max ? Math.max(0, Math.min(100, (cur / max) * 100)) : 0;
    return `<div class="bar ${kind}"><i style="width:${w}%"></i><span>${label || `${fmt(cur)} / ${fmt(max)}`}</span></div>`;
  }

  function viewHud() {
    const d = P.view.derived, need = P.view.xpToNext;
    return `
      <div class="hud-top">
        ${heroSprite()}
        <div class="hud-who">
          <div class="hud-name">${esc(P.name)}</div>
          <div class="small muted">${CLASSES[P.cls].name} · ${P.rebirths ? `<span class="tag gold num" title="Số lần chuyển sinh">CS ${P.rebirths}</span> ` : ''}Cấp ${P.level}</div>
        </div>
        <div class="gold">${icon('two-coins')}${fmt(P.gold)}</div>
        <button class="hud-btn" data-act="friends-open" aria-label="Bạn bè${friendsBadge() ? `, ${friendsBadge()} tin mới` : ''}">👥${friendsBadge() ? `<span class="points-dot">${friendsBadge()}</span>` : ''}</button>
        <button class="hud-btn" data-act="notes-open" aria-label="Thông báo${notesUnread() ? `, ${notesUnread()} tin mới` : ''}">🔔${notesUnread() ? `<span class="points-dot">${notesUnread()}</span>` : ''}</button>
        <button class="hud-btn" data-act="mail-open" aria-label="Hộp thư${mail.unread ? `, ${mail.unread} thư mới` : ''}">${icon('envelope')}${mail.unread ? `<span class="points-dot">${mail.unread}</span>` : ''}</button>
      </div>
      <div class="bars">
        ${bar('hp', P.hp, d.maxHp, `❤ ${fmt(P.hp)} / ${fmt(d.maxHp)}`)}
        ${bar('mp', P.mp || 0, d.maxMp, `💧 ${fmt(P.mp || 0)} / ${fmt(d.maxMp)}`)}
        ${P.level >= RULES.maxLevel ? bar('xp', 1, 1, 'Cấp tối đa') : bar('xp', P.xp, need, `⭐ ${Math.floor((P.xp / need) * 100)}%`)}
      </div>`;
  }

  // ---------- Hộp thư ----------
  async function loadMail(op) {
    try {
      const r = await Net.mail(op);
      if (op === 'delete_read') toast('Đã xóa thư đã đọc.');
      mail.list = r.mails; mail.unread = r.unread;
    } catch (e) { toast(e.msg, true); mail.list = mail.list || []; }
    if (mail.open) render();
  }

  // đồ riêng từng món trong thư: "gear:<mẫu>:<độ hiếm>:<+N>"
  function mailItemName(id) {
    const g = id.startsWith('gear:') && id.split(':');
    if (g && ITEMS[g[1]]) return `${ITEMS[g[1]].name}${+g[2] ? ` (${RARITY[g[2]]})` : ''}${+g[3] ? ` +${g[3]}` : ''}`;
    return ITEMS[id] ? ITEMS[id].name : id;
  }
  function mailGifts(m) {
    return [m.gold ? `${fmt(m.gold)} vàng` : '', m.xp ? `${fmt(m.xp)} kinh nghiệm` : '']
      .concat(Object.entries(m.items).map(([id, n]) => `${mailItemName(id)}${n > 1 ? ` ×${n}` : ''}`))
      .filter(Boolean).join(' · ');
  }

  // ---------- Bạn bè, tin riêng ----------
  const friendsBadge = () => friendsUi.dm + ((friendsUi.data && friendsUi.data.incoming.length) || 0);
  async function loadFriends() {
    try { friendsUi.data = await Net.friends('list'); friendsUi.dm = friendsUi.data.unread; } catch (e) { /* thử lại sau */ }
    render();
  }
  async function friendOp(op, payload) {
    try {
      const r = await Net.friends(op, payload);
      friendsUi.data = r; friendsUi.dm = r.unread;
      if (r.msg) toast(r.msg);
    } catch (e) { toast(e.msg, true); }
    if (dialog && dialog.type === 'player') dialog = null;
    render();
  }
  async function openChat(uid) {
    friendsUi.open = true;
    friendsUi.chat = { uid, data: null };
    render();
    try {
      const r = await Net.dm('history', { uid });
      if (friendsUi.chat && friendsUi.chat.uid === uid) friendsUi.chat.data = r;
      friendsUi.dm = r.unread;
      if (friendsUi.data) { const f = friendsUi.data.friends.find((x) => x.id === uid); if (f) f.unread = 0; }
    } catch (e) { toast(e.msg, true); friendsUi.chat = null; }
    render();
  }
  function onDm(m) {
    const me = Net.userId, other = m.from === me ? m.to : m.from;
    const c = friendsUi.chat;
    if (friendsUi.open && c && c.uid === other && c.data) {
      c.data.messages.push(m);
      // đang mở cuộc trò chuyện: đánh dấu đã đọc
      if (m.from !== me) Net.dm('history', { uid: other }).then((r) => { friendsUi.dm = r.unread; }).catch(() => {});
      render();
      return;
    }
    if (m.from === me) return;
    friendsUi.dm += 1;
    if (friendsUi.data) { const f = friendsUi.data.friends.find((x) => x.id === other); if (f) f.unread += 1; }
    toast(`💬 ${m.name}: ${m.text}`);
    Sound.play('mail');
    if (P && !P.battle) refreshHud();
  }
  function refreshHud() { const h = $('#hud'); if (h && P && !P.battle) h.innerHTML = viewHud(); }
  const hhmm = (t) => new Date(t).toLocaleString('vi-VN', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' });

  function viewFriends() {
    const c = friendsUi.chat;
    if (c) {
      const d = c.data;
      const head = `<div class="row"><h2 class="display grow">💬 ${d ? esc(d.with.name) : 'Đang mở…'}</h2><button class="btn" data-act="dm-back">Về</button></div>`;
      if (!d) return head;
      return `${head}<div class="card">
        <p class="small muted">${d.with.online ? '<span style="color:var(--good)">● Đang online</span>' : '○ Không online, sẽ thấy tin khi vào game'}</p>
        <div class="dm-log" id="dm-log">${d.messages.length ? d.messages.map((m) => `<div class="dm ${m.from === Net.userId ? 'me' : ''}"><span>${esc(m.text)}</span><small>${hhmm(m.at)}</small></div>`).join('') : '<p class="small muted">Chưa có tin nào. Chào một câu đi!</p>'}</div>
        <form id="dm-form" class="chat-form" autocomplete="off"><input type="text" id="dm-input" maxlength="200" placeholder="Nhắn cho ${esc(d.with.name)}…" aria-label="Tin nhắn"><button class="btn primary" type="submit">Gửi</button></form>
      </div>`;
    }
    const d = friendsUi.data;
    const head = `<div class="row"><h2 class="display grow">👥 Bạn bè</h2><button class="btn" data-act="friends-close">Đóng</button></div>`;
    if (!d) return head + '<p class="small muted">Đang tải…</p>';
    const person = (f) => `<div class="name">${esc(f.name)}</div><div class="small muted">${f.level ? `Cấp ${f.level}` : ''}${f.cls && CLASSES[f.cls] ? ` ${CLASSES[f.cls].name}` : ''}</div>`;
    return `${head}
      <div class="card"><form id="friend-add" class="chat-form" autocomplete="off"><input type="text" id="friend-name" maxlength="20" placeholder="Tên nhân vật muốn kết bạn"><button class="btn primary" type="submit">Kết bạn</button></form>
        <p class="small muted">Hoặc chạm vào người chơi trên bản đồ → Kết bạn. Tối đa ${d.max} bạn. Chỉ nhắn riêng được cho bạn bè.</p></div>
      ${d.incoming.length ? `<div class="card"><h3>Lời mời kết bạn</h3><div class="list">${d.incoming.map((f) => `<div class="item"><div class="grow">${person(f)}</div>
        <button class="btn small-btn" data-act="friend-op" data-op="decline" data-uid="${f.id}">Từ chối</button><button class="btn small-btn primary" data-act="friend-op" data-op="accept" data-uid="${f.id}">Nhận</button></div>`).join('')}</div></div>` : ''}
      <div class="card"><h3>Bạn bè (${d.friends.length})</h3>${d.friends.length ? `<div class="list">${d.friends.map((f) => `<div class="item"><div class="grow">
          <div class="name">${f.online ? '<span style="color:var(--good)" title="Đang online">●</span>' : '<span class="muted" title="Không online">○</span>'} ${esc(f.name)}${f.unread ? ` <span class="tag gold num">${f.unread} tin mới</span>` : ''}</div>
          <div class="small muted">${f.level ? `Cấp ${f.level}` : ''}${f.cls && CLASSES[f.cls] ? ` ${CLASSES[f.cls].name}` : ''}</div>
          <div class="btn-row"><button class="btn small-btn" data-act="home-visit" data-uid="${f.id}">🏡 Thăm nhà</button>${friendsUi.confirm === f.id
            ? `<button class="btn small-btn danger" data-act="friend-op" data-op="remove" data-uid="${f.id}">Xóa thật?</button>`
            : `<button class="btn small-btn" data-act="friend-ask" data-uid="${f.id}">Xóa bạn</button>`}</div></div>
          <button class="btn ${f.unread ? 'primary' : ''}" data-act="dm-open" data-uid="${f.id}">💬 Nhắn</button></div>`).join('')}</div>` : '<p class="small muted">Chưa có bạn nào.</p>'}</div>
      ${d.outgoing.length ? `<div class="card"><h3>Đã mời, đang chờ</h3><div class="list">${d.outgoing.map((f) => `<div class="item"><div class="grow">${person(f)}</div><button class="btn small-btn" data-act="friend-op" data-op="decline" data-uid="${f.id}">Rút lời mời</button></div>`).join('')}</div></div>` : ''}`;
  }

  function viewMail() {
    const all = mail.list;
    const hasGift = (m) => !m.claimed && !!mailGifts(m);
    const list = all && all.filter((m) => mail.filter === 'unread' ? !m.claimed : mail.filter === 'gift' ? hasGift(m) : true);
    const filters = [['all', 'Tất cả'], ['unread', 'Chưa đọc'], ['gift', 'Có quà']];
    return `<div class="row"><h2 class="display grow">Hộp thư</h2><button class="btn" data-act="mail-close">Đóng</button></div>
      ${all ? `<div class="row" id="mail-tools"><div class="seg grow">${filters.map(([k, label]) => `<button class="btn small-btn ${mail.filter === k ? 'primary' : ''}" data-act="mail-filter" data-f="${k}">${label}</button>`).join('')}</div>
        ${all.some((m) => !m.claimed) ? '<button class="btn small-btn primary" data-act="mail_claim_all">Nhận tất cả</button>' : ''}
        ${all.some((m) => m.claimed) ? '<button class="btn small-btn" data-act="mail-delete-read">Xóa thư đã đọc</button>' : ''}</div>
        <p class="small muted">Thư quá 30 ngày tự xóa, trừ thư còn quà chưa nhận.</p>` : ''}
      ${list == null ? '<p class="small muted">Đang tải…</p>'
        : list.length === 0 && all.length ? '<div class="card"><p class="small muted">Không có thư nào ở mục này.</p></div>'
        : list.length === 0 ? '<div class="card"><p class="small muted">Chưa có thư nào. Quà nhận lúc vắng mặt (trùm thế giới) và quà của Ban Quản Trị sẽ gửi vào đây.</p></div>'
        : `<div class="list">${list.map((m) => {
          const gifts = mailGifts(m);
          return `<div class="card mail ${m.claimed ? 'read' : ''}">
            <div class="row"><b class="grow">${esc(m.subject)}</b><span class="small muted">${new Date(m.at).toLocaleString('vi-VN')}</span></div>
            ${m.body ? `<p class="small">${esc(m.body)}</p>` : ''}
            ${gifts ? `<p class="small" style="color:var(--gold)">Quà: ${gifts}</p>` : ''}
            ${m.claimed ? `<span class="tag good">${gifts ? 'Đã nhận' : 'Đã đọc'}</span>`
              : `<button class="btn ${gifts ? 'primary' : ''}" data-act="mail_claim" data-id="${m.id}">${gifts ? 'Nhận quà' : 'Đánh dấu đã đọc'}</button>`}
          </div>`;
        }).join('')}</div>`}`;
  }

  // ---------- Tạo nhân vật ----------
  function viewCreate() {
    return `
      <div class="intro">
        ${sprite('shadow_dragon', '', 'Hắc Long')}
        <h1>Hắc Long</h1>
        <p>Hắc Long đã khủng bố vùng đất này nhiều năm. Rèn luyện qua sáu vùng đất, hạ các trùm canh giữ và tiêu diệt nó.</p>
      </div>
      <form id="create" class="card" autocomplete="off">
        <label class="field" for="hero-name">Tên nhân vật
          <input type="text" id="hero-name" maxlength="16" placeholder="Ví dụ: Lãng Khách" required>
        </label>
        <div class="field" style="display:grid;gap:6px"><span style="font-weight:600">Chọn lớp</span>
          <div class="classes">
            ${Object.entries(CLASSES).map(([id, c]) => `
              <button type="button" class="class-opt" data-cls="${id}" aria-pressed="${pickCls === id}">
                ${icon(c.icon, 'lg')}
                <span class="grow" style="display:grid;gap:2px;min-width:0">
                  <b>${c.name}</b>
                  <span class="small muted">${c.desc}</span>
                  <span class="stats">STR ${c.base.str} · AGI ${c.base.agi} · VIT ${c.base.vit} · ENE ${c.base.ene} · ${c.points} điểm / cấp</span>
                  <span class="small" style="color:var(--gold)">Kỹ năng: ${c.skills[0].name}. ${c.skills[0].desc}</span>
                </span>
              </button>`).join('')}
          </div>
        </div>
        <button class="btn primary block" type="submit">Bắt đầu hành trình</button>
      </form>
      <p class="small muted" style="text-align:center">Tài khoản <b>${esc(Net.username)}</b> · <button class="btn" data-act="logout">Đăng xuất</button></p>`;
  }

  // ---------- Đăng nhập ----------
  function viewLoading() {
    return `<div class="intro">${sprite('shadow_dragon', '', 'Hắc Long')}<h1>Hắc Long</h1><p>Đang kết nối máy chủ...</p></div>`;
  }

  function viewLogin() {
    const reg = authMode === 'register';
    const lg = window.I18N ? window.I18N.lang : 'vi';
    return `
      <p class="small" style="text-align:right;margin:0" data-notr><button class="btn small-btn" data-act="lang" data-lang="${lg === 'vi' ? 'en' : 'vi'}">${lg === 'vi' ? 'English' : 'Tiếng Việt'}</button></p>
      <div class="intro">
        ${sprite('shadow_dragon', '', 'Hắc Long')}
        <h1>Hắc Long</h1>
        <p>${reg ? 'Tạo tài khoản để lưu nhân vật trên máy chủ và chơi trên mọi thiết bị.' : 'Đăng nhập để tiếp tục hành trình.'}</p>
      </div>
      <form id="auth" class="card">
        <label class="field" for="auth-user">Tên đăng nhập
          <input type="text" id="auth-user" maxlength="20" autocomplete="username" autocapitalize="none" spellcheck="false" required>
        </label>
        <label class="field" for="auth-pass">Mật khẩu
          <input type="password" id="auth-pass" maxlength="72" autocomplete="${reg ? 'new-password' : 'current-password'}" required>
        </label>
        ${reg ? '<p class="small muted">Tên đăng nhập 3–20 ký tự: chữ không dấu, số, dấu gạch dưới. Mật khẩu từ 6 ký tự.</p>' : ''}
        <button class="btn primary block" type="submit" ${busy ? 'disabled' : ''}>${reg ? 'Tạo tài khoản' : 'Đăng nhập'}</button>
        <button class="btn block" type="button" data-auth="${reg ? 'login' : 'register'}">${reg ? 'Đã có tài khoản? Đăng nhập' : 'Chưa có tài khoản? Đăng ký'}</button>
      </form>`;
  }

  // ---------- Làng ----------
  function nextBossIndex() {
    return ZONES.findIndex((z) => !P.bosses.includes(z.boss.id));
  }

  // Menu (Phase 9, U3): các mục trước đây gom trong tab Khác, mỗi mục một màn
  function viewJourney() {
    const d = P.view.derived, cost = P.view.restCost, full = P.hp >= d.maxHp && (P.mp || 0) >= d.maxMp;
    const ni = nextBossIndex();
    const pots = ['potion_s', 'potion_m', 'potion_l'].reduce((s, id) => s + (P.inv[id] || 0), 0);
    return `
      ${P.victory ? viewVictory() : ''}
      <div class="card">
        <div class="row">${icon('campfire', 'lg')}<div class="grow"><h3>Hồi máu</h3><p class="small muted">${full ? 'Máu và MP đang đầy.' : `Gặp Chủ Quán Trọ ở Làng để nghỉ${cost ? ` (${fmt(cost)} vàng)` : ' (miễn phí)'}, hoặc về Nhà uống nước giếng.`}</p></div></div>
      </div>

      <div class="card">
        <div class="row"><h3 class="grow">Hành trình diệt rồng</h3><span class="tag gold num">${P.bosses.length}/${ZONES.length} trùm</span></div>
        <div class="journey">
          ${ZONES.map((z, i) => `<div class="step ${P.bosses.includes(z.boss.id) ? 'done' : i === ni ? 'next' : ''}">${sprite(z.boss.id, '', z.boss.name)}<span>${z.boss.name}</span></div>`).join('')}
        </div>
        ${ni >= 0 ? `<p class="small muted">Mục tiêu kế tiếp: hạ <b style="color:var(--parch)">${ZONES[ni].boss.name}</b> (cấp ${ZONES[ni].boss.level}) ở ${ZONES[ni].name}.</p>` : '<p class="small" style="color:var(--gold)">Bạn đã hạ tất cả trùm. Vùng đất đã bình yên.</p>'}
      </div>

      ${pots === 0 ? `<div class="card"><div class="row">${icon('health-potion', 'lg')}<div class="grow"><h3>Hết bình máu</h3><p class="small muted">Mua ở Bà Lang trong Làng, hoặc hái Thảo Dược nhờ bà pha.</p></div></div></div>` : ''}

      ${wb.alive ? '' : wb.nextAt ? `<div class="card"><div class="row">${sprite('ancient_dragon', '', '')}<div class="grow"><h3>Trùm thế giới</h3><p class="small muted">${esc(wb.name)} sẽ xuất hiện ở Tế Đàn sau khoảng ${Math.max(1, Math.round((wb.nextAt - wb.skew - Date.now()) / 60000))} phút. Cả server cùng đánh, chia thưởng theo sát thương.</p></div></div></div>` : ''}
`;
  }

  function viewStats() {
    return `
      <div class="card">
        <h3>Thành tích</h3>
        <div class="stat-grid">
          <div class="stat"><span class="small muted">Quái đã hạ</span><b>${fmt(P.kills)}</b></div>
          <div class="stat"><span class="small muted">Số lần gục ngã</span><b>${fmt(P.deaths)}</b></div>
        </div>
      </div>

      ${viewAchievements()}`;
  }

  // lựa chọn hiển thị lưu ở trình duyệt (chỉ giao diện)
  function pref(k, d) { try { return localStorage.getItem(k) || d; } catch (e) { return d; } }
  function setPref(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* bị chặn: chỉ đổi lần này */ } }

  const skillMp = (k) => L.skillMp(k, P.level, RULES.skillMpPerLevel);

  function viewSettings() {
    const lg = window.I18N ? window.I18N.lang : 'vi';
    return `
      <div class="card" data-notr><div class="row"><h3 class="grow">Ngôn ngữ / Language</h3>
        <div class="btn-row"><button class="btn ${lg === 'vi' ? 'primary' : ''}" data-act="lang" data-lang="vi" aria-pressed="${lg === 'vi'}">Tiếng Việt</button>
        <button class="btn ${lg === 'en' ? 'primary' : ''}" data-act="lang" data-lang="en" aria-pressed="${lg === 'en'}">English</button></div></div></div>
      <div class="card"><div class="row"><h3 class="grow">Bản đồ</h3>
        <div class="btn-row">${[['day', '☀️ Sáng'], ['night', '🌙 Tối'], ['auto', '🕒 Tự động']].map(([k, l]) => `<button class="btn ${pref('hl-theme', 'auto') === k ? 'primary' : ''}" data-act="theme" data-theme="${k}" aria-pressed="${pref('hl-theme', 'auto') === k}">${l}</button>`).join('')}</div></div>
        <p class="small muted">Tự động: sáng tối theo giờ trong game.</p></div>
      <div class="card">
        <div class="row">${icon(Sound.on ? 'speaker' : 'speaker-off', 'lg')}<h3 class="grow">Âm thanh</h3>
          <button class="btn" data-act="sound-toggle" aria-pressed="${Sound.on}">${Sound.on ? 'Đang bật' : 'Đang tắt'}</button></div>
        <label class="small volume">Âm lượng <input type="range" id="volume" min="0" max="100" value="${Math.round(Sound.volume * 100)}" ${Sound.on ? '' : 'disabled'}></label>
        <div class="row" style="margin-top:10px"><span class="grow">🎵 Nhạc nền <span class="small muted">(đổi theo nơi đang đứng, ngày đêm, trận đánh)</span></span>
          <button class="btn" data-act="music-toggle" aria-pressed="${Sound.musicOn}">${Sound.musicOn ? 'Đang bật' : 'Đang tắt'}</button></div>
        <label class="small volume">Âm lượng nhạc <input type="range" id="music-volume" min="0" max="100" value="${Math.round(Sound.musicVolume * 100)}" ${Sound.musicOn ? '' : 'disabled'}></label>
      </div>

      <div class="card">
        <h3>Dữ liệu</h3>
        <p class="small muted">Nhân vật lưu trên máy chủ, tài khoản <b>${esc(Net.username)}</b>.</p>
        <div class="btn-row" style="margin-bottom:8px">
          <button class="btn" data-act="logout">Đăng xuất</button>
          <button class="btn" data-act="pw-toggle">Đổi mật khẩu</button>
        </div>
        ${pwForm ? `<form id="pw-form" class="pw-form">
          <label class="field" for="pw-cur">Mật khẩu hiện tại<input type="password" id="pw-cur" autocomplete="current-password" required></label>
          <label class="field" for="pw-new">Mật khẩu mới<input type="password" id="pw-new" autocomplete="new-password" minlength="6" maxlength="72" required></label>
          <p class="small muted">Đổi xong, các thiết bị khác sẽ bị đăng xuất.</p>
          <button class="btn primary" type="submit">Lưu mật khẩu mới</button>
        </form>` : ''}
        <button class="btn" data-act="logout-all" style="margin-bottom:8px">Đăng xuất mọi thiết bị</button>
        ${blocked.length ? `<p class="small muted">Đã chặn chat:</p><div class="list">${blocked.map((b) => `<div class="item"><span class="grow">${esc(b.name)}</span><button class="btn small-btn" data-act="unblock" data-uid="${b.id}">Bỏ chặn</button></div>`).join('')}</div>` : ''}
        ${confirmReset
          ? `<p class="small" style="color:var(--bad)">Xóa nhân vật ${esc(P.name)} và chơi lại từ đầu? Không thể hoàn tác.</p>
             <div class="btn-row"><button class="btn" data-act="reset-cancel">Giữ lại</button><button class="btn danger" data-act="reset-yes">Xóa và chơi lại</button></div>`
          : `<button class="btn" data-act="reset-ask">Chơi lại từ đầu</button>`}
      </div>`;
  }

  // ---------- Bang hội ----------
  const ROLES = { leader: 'Bang chủ', officer: 'Phó bang', member: 'Thành viên' };

  function viewGuildCard() {
    const g = P.guild;
    return `<div class="card"><div class="row">${icon('crossed-swords', 'lg')}<div class="grow"><h3>Bang hội</h3>
      <p class="small muted">${g ? `<span class="guild-tag">[${esc(g.tag)}]</span> ${esc(g.name)} · cấp ${g.level} · ${ROLES[g.role]}` : 'Chưa vào bang nào. Vào bang để có kênh chat riêng và thêm kinh nghiệm mỗi trận.'}</p></div></div>
      <button class="btn block" data-act="guild-open">${g ? 'Xem bang' : 'Tìm hoặc lập bang'}</button></div>`;
  }

  async function loadGuild() {
    try {
      if (P.guild) { guildUi.info = (await Net.guild('info')).guild; }
      else { const r = await Net.guild('list', { q: guildUi.q }); guildUi.list = r.guilds; guildUi.requested = r.requested; guildUi.info = null; }
    } catch (e) { toast(e.msg, true); }
    if (guildUi.open) render();
  }

  // thao tác bang qua kênh "guild"; server trả lại thông tin bang mới
  async function guildOp(op, payload) {
    try {
      const r = await Net.guild(op, payload);
      if (r.msg) toast(r.msg);
      guildUi.confirm = null;
      if (r.guild !== undefined) guildUi.info = r.guild;
      if (op === 'join' || op === 'cancel' || !r.guild) await loadGuild(); else render();
    } catch (e) { toast(e.msg, true); }
  }

  function viewGuild() {
    const head = `<div class="row"><h2 class="display grow">Bang hội</h2><button class="btn" data-act="guild-close">Đóng</button></div>`;
    if (!P.guild) {
      const list = guildUi.list;
      return `${head}
        <div class="card"><h3>Lập bang mới</h3>
          <form id="guild-create" class="gift-form">
            <input type="text" name="name" maxlength="20" placeholder="Tên bang (3–20 ký tự)" required>
            <input type="text" name="tag" maxlength="4" placeholder="Ký hiệu 2–4 chữ, vd. RONG" required autocapitalize="characters">
            <button class="btn primary" type="submit" ${P.gold < RULES.guildCost ? 'disabled' : ''}>${icon('two-coins')} Lập bang · ${fmt(RULES.guildCost)} vàng</button>
          </form></div>
        <div class="card"><h3>Tìm bang</h3>
          <form id="guild-search" class="chat-form"><input type="text" id="guild-q" placeholder="Tên hoặc ký hiệu" value="${esc(guildUi.q)}"><button class="btn" type="submit">Tìm</button></form>
          ${list == null ? '<p class="small muted">Đang tải…</p>' : list.length === 0 ? '<p class="small muted">Chưa có bang nào.</p>'
            : `<div class="list">${list.map((g) => {
              const asked = guildUi.requested.includes(g.id), full = g.members >= g.capacity;
              return `<div class="item"><div class="grow"><div class="name"><span class="guild-tag">[${esc(g.tag)}]</span> ${esc(g.name)}</div>
                <div class="small muted">Cấp ${g.level} · ${g.members}/${g.capacity} người · ${g.open ? 'vào tự do' : 'phải xin vào'}</div></div>
                ${asked ? `<button class="btn" data-act="guild-op" data-op="cancel" data-id="${g.id}">Rút đơn</button>`
                  : `<button class="btn primary" data-act="guild-op" data-op="join" data-id="${g.id}" ${full ? 'disabled' : ''}>${full ? 'Đủ người' : g.open ? 'Vào' : 'Xin vào'}</button>`}</div>`;
            }).join('')}</div>`}
        </div>`;
    }
    const g = guildUi.info;
    if (!g) return head + '<p class="small muted">Đang tải…</p>';
    const staff = g.role === 'leader' || g.role === 'officer', leader = g.role === 'leader';
    const pct = g.next_fund ? Math.round((g.fund / g.next_fund) * 100) : 100;
    const memberRow = (m) => {
      const me = m.id === Net.userId;
      const acts = [];
      if (leader && !me && m.role === 'member') acts.push(['promote', 'Phong phó bang']);
      if (leader && !me && m.role === 'officer') acts.push(['demote', 'Bỏ chức']);
      if (leader && !me) acts.push(['transfer', 'Nhường bang chủ']);
      if (!me && m.role !== 'leader' && (leader || (g.role === 'officer' && m.role === 'member'))) acts.push(['kick', 'Mời ra']);
      const ask = guildUi.confirm && guildUi.confirm.uid === m.id ? guildUi.confirm : null;
      return `<div class="item member"><div class="grow">
        <div class="name">${esc(m.name)}${me ? ' <span class="small muted">(bạn)</span>' : ` <button class="btn small-btn" data-act="home-visit" data-uid="${m.id}">🏡 Thăm nhà</button>`}</div>
        <div class="small muted">${ROLES[m.role]} · ${m.level ? `Cấp ${m.level}` : ''}${m.cls && CLASSES[m.cls] ? ` ${CLASSES[m.cls].name}` : ''} · góp ${fmt(m.contributed)} vàng</div>
        ${ask ? `<div class="btn-row"><span class="small" style="color:var(--bad)">${ask.label} ${esc(m.name)}?</span><button class="btn small-btn" data-act="guild-confirm-no">Thôi</button><button class="btn small-btn danger" data-act="guild-op" data-op="${ask.op}" data-uid="${m.id}">Đồng ý</button></div>`
          : acts.length ? `<div class="btn-row">${acts.map(([op, label]) => `<button class="btn small-btn" data-act="guild-ask" data-op="${op}" data-uid="${m.id}" data-label="${label}">${label}</button>`).join('')}</div>` : ''}
      </div></div>`;
    };
    return `${head}
      <div class="card">
        <div class="row"><h3 class="grow"><span class="guild-tag">[${esc(g.tag)}]</span> ${esc(g.name)}</h3><span class="tag gold num">Cấp ${g.level}</span></div>
        ${g.notice ? `<p>“${esc(g.notice)}”</p>` : ''}
        ${bar('xp', g.fund, g.next_fund || g.fund, g.next_fund ? `Quỹ ${fmt(g.fund)} / ${fmt(g.next_fund)}` : `Quỹ ${fmt(g.fund)} · cấp tối đa`)}
        <p class="small muted">${g.members.length}/${g.capacity} thành viên · +${Math.round(g.xp_bonus * 100)}% kinh nghiệm mỗi trận · ${g.open ? 'ai cũng vào được' : 'phải xin vào'}</p>
        <form id="guild-donate" class="chat-form"><input type="number" id="donate-amount" min="${RULES.guildMinDonate}" step="100" placeholder="Số vàng góp quỹ"><button class="btn primary" type="submit">Góp</button></form>
        ${g.boss_damage ? `<p class="small muted">🐉 Cả bang đã gây ${fmt(g.boss_damage)} sát thương lên trùm thế giới.</p>` : ''}
      </div>
      ${viewGuildQuest(g.quest)}
      ${viewGuildWar(g, staff)}
      ${staff ? `<div class="card"><h3>Quản lý</h3>
        <form id="guild-settings" class="gift-form">
          <input type="text" name="notice" maxlength="120" placeholder="Thông báo cho cả bang" value="${esc(g.notice || '')}">
          <label class="small"><input type="checkbox" name="open" ${g.open ? 'checked' : ''}> Ai cũng vào được (bỏ chọn: phải xin, bang chủ/phó bang duyệt)</label>
          <button class="btn" type="submit">Lưu</button>
        </form>
        ${g.requests.length ? `<h3>Đơn xin vào</h3><div class="list">${g.requests.map((r) => `<div class="item"><div class="grow"><div class="name">${esc(r.name)}</div><div class="small muted">${r.level ? `Cấp ${r.level}` : ''}</div></div>
          <button class="btn small-btn" data-act="guild-op" data-op="reject" data-uid="${r.id}">Từ chối</button><button class="btn small-btn primary" data-act="guild-op" data-op="accept" data-uid="${r.id}">Nhận</button></div>`).join('')}</div>` : '<p class="small muted">Không có đơn xin vào nào.</p>'}
      </div>` : ''}
      <div class="card"><h3>Thành viên</h3><div class="list">${g.members.map(memberRow).join('')}</div></div>
      <div class="card">
        ${guildUi.confirm && guildUi.confirm.op === (leader && g.members.length === 1 ? 'disband' : 'leave') && !guildUi.confirm.uid
          ? `<p class="small" style="color:var(--bad)">${leader && g.members.length === 1 ? 'Giải tán bang? Quỹ bang sẽ mất.' : 'Rời bang?'}</p>
             <div class="btn-row"><button class="btn" data-act="guild-confirm-no">Thôi</button><button class="btn danger" data-act="guild-op" data-op="${leader && g.members.length === 1 ? 'disband' : 'leave'}">Đồng ý</button></div>`
          : `<button class="btn block" data-act="guild-ask" data-op="${leader && g.members.length === 1 ? 'disband' : 'leave'}">${leader && g.members.length === 1 ? 'Giải tán bang' : 'Rời bang'}</button>`}
        ${leader && g.members.length > 1 ? '<p class="small muted">Bang chủ muốn rời thì nhường bang chủ cho người khác trước.</p>' : ''}
      </div>`;
  }

  // Chiến bang (H5): trận đang chiến, lời tuyên chiến đang chờ, tuyên chiến theo ký hiệu bang, lịch sử.
  function viewGuildWar(g, staff) {
    const w = g.war, pend = g.war_pending, hist = g.war_history || [];
    const left = w ? Math.max(0, Math.ceil((w.ends_at * 1000 - Date.now()) / 60000)) : 0;
    const out = { win: ['Thắng', 'good'], lose: ['Thua', 'bad'], draw: ['Hòa', ''] };
    return `<div class="card" id="guild-war"><h3>⚔ Chiến bang</h3>
      ${w ? `<p>Đang chiến với <span class="guild-tag">[${esc(w.enemy.tag)}]</span> ${esc(w.enemy.name)}: <b class="num">${w.mine} – ${w.theirs}</b> <span class="small muted">· còn ${left} phút</span></p>
          <p class="small muted">Thắng thành viên bang địch ở đấu trường để ghi điểm (mỗi đối thủ tối đa vài lần). Tên người bang địch trên bản đồ màu đỏ.</p>
          ${staff ? '<button class="btn danger" data-act="guild-war-surrender">Đầu hàng</button>' : ''}`
        : pend && staff ? `<p>Bang <span class="guild-tag">[${esc(pend.tag)}]</span> ${esc(pend.name)} tuyên chiến bang bạn!</p>
          <div class="btn-row"><button class="btn" data-act="guild-op" data-op="war_decline">Từ chối</button><button class="btn primary" data-act="guild-op" data-op="war_accept">Nhận chiến</button></div>`
        : staff ? `<form id="guild-war-form" class="chat-form"><input type="text" id="war-tag" maxlength="4" placeholder="Ký hiệu bang địch" autocapitalize="characters"><button class="btn primary" type="submit">Tuyên chiến</button></form>
          <p class="small muted">Bang kia cần có bang chủ / phó bang online để nhận. Trận kéo dài ${RULES.warMinutes} phút; bang thắng được quỹ +${fmt(RULES.warFund)}, ai ghi điểm nhận ${fmt(RULES.warGold)} vàng.</p>`
        : '<p class="small muted">Bang chưa chiến với ai. Bang chủ / phó bang tuyên chiến.</p>'}
      ${hist.length ? `<div class="list">${hist.map((h) => `<div class="item"><div class="grow"><span class="guild-tag">[${esc(h.enemy ? h.enemy.tag : '?')}]</span> ${esc(h.enemy ? h.enemy.name : 'Bang đã giải tán')}</div><span class="num">${h.mine} – ${h.theirs}</span> <span class="tag ${out[h.result][1]}">${out[h.result][0]}</span></div>`).join('')}</div>` : ''}
    </div>`;
  }

  // ---------- Sổ tay quái vật ----------
  let bestiaryOpen = false;
  function viewBestiary() {
    const all = ZONES.flatMap((z) => z.monsters.concat([z.boss]));
    const count = (id) => (P.bestiary && P.bestiary[id]) || 0;
    const seen = all.filter((m) => count(m.id) > 0).length;
    const cells = all.map((m) => {
      const n = count(m.id), stars = n >= 100 ? '★★' : n >= 25 ? '★' : '';
      return `<div class="beast ${n ? '' : 'unseen'}" title="${n ? esc(m.name) : '???'}">
        ${sprite(m.id, '', n ? m.name : '')}
        <span class="small">${n ? esc(m.name) : '???'}</span>
        <span class="small num">${n ? `${fmt(n)} con` : ''}${stars ? ` <b class="stars">${stars}</b>` : ''}</span>
      </div>`;
    }).join('');
    return `<div class="card">
      <div class="row">${icon('open-book', 'lg')}<div class="grow"><h3>Sổ tay quái vật</h3>
        <p class="small muted">Hạ 25 con một loài: +5% sát thương lên loài đó (★), 100 con: +10% (★★), mỗi mốc kèm thưởng vàng.</p></div>
        <span class="tag gold num">${seen}/${all.length}</span></div>
      ${bestiaryOpen ? `<div class="bestiary">${cells}</div>` : ''}
      <button class="btn block" data-act="bestiary-toggle">${bestiaryOpen ? 'Thu gọn' : 'Xem sổ tay'}</button>
    </div>`;
  }

  function viewVictory() {
    return `
      <div class="card victory">
        ${sprite('shadow_dragon', '', 'Hắc Long đã chết')}
        <h1>Chiến thắng!</h1>
        <p>${esc(P.name)} đã tiêu diệt Hắc Long ở cấp ${P.level} sau ${fmt(P.kills)} trận đánh. Bạn vẫn có thể tiếp tục luyện cấp và săn quái.</p>
      </div>`;
  }

  // ---------- Nhân vật ----------
  // 4 chỉ số như MU; chỉ số nào tăng tấn công / phòng thủ tùy lớp (CLASSES[lớp].derived)
  const STAT_INFO = {
    str: ['Sức mạnh', 'Tấn công (Kiếm Sĩ, Đấu Sĩ, một phần Tiên Nữ)'],
    agi: ['Nhanh nhẹn', 'Chí mạng, né, phòng thủ; tấn công của Tiên Nữ'],
    vit: ['Thể lực', 'Máu tối đa'],
    ene: ['Năng lượng', 'MP tối đa; tấn công của Phù Thủy, Đấu Sĩ'],
  };

  // Tên món đồ kèm cấp nâng cấp (+1…+11) nếu có.
  const upLevel = (id) => (P.upgrades && P.upgrades[id]) || 0;
  // cấp tính chỉ số: từ +10 mỗi cấp gấp đôi (như Engine.effective_level)
  const effLevel = (l) => L.effLevel(l, UPGRADE.double_from);
  // màu viền theo cấp nâng (+7, +9, +11)
  const upClass = L.upClass;
  // Món đồ theo id: đồ thường trong ITEMS, đồ chỉ số ngẫu nhiên (id bắt đầu bằng #) do server gửi.
  const isGear = (id) => typeof id === 'string' && id[0] === '#';
  const itemOf = (id) => (isGear(id) ? P.view.gear[id] : ITEMS[id]);
  const RARITY = { 1: 'Tốt', 2: 'Hiếm', 3: 'Sử Thi' };
  // nhãn ngắn cho đồ bản riêng trong danh sách chọn: độ hiếm và / hoặc cấp nâng
  const gearTag = (id) => { const it = itemOf(id), up = upLevel(id); return [it.rarity ? RARITY[it.rarity] : '', up ? `+${up}` : ''].filter(Boolean).map((x) => ` (${x})`).join(''); };
  const itemName = (id) => {
    const it = itemOf(id);
    const name = it.rarity ? `<span class="rar-${it.rarity}">${esc(it.name)}</span>` : it.name;
    return name + (upLevel(id) ? ` <span class="up-lv">+${upLevel(id)}</span>` : '') + (it.locked ? ' <span class="lock-ic" title="Đã khóa">🔒</span>' : '');
  };
  const bonusText = (it) => (it.bonus ? Object.entries(it.bonus).sort((a, b) => b[1] - a[1]).map(([k, v]) => `+${v} ${STAT_INFO[k][0]}`).join(', ') : '');

  function itemStat(it, id) {
    const b = id ? P.view.bonus[id] || 0 : 0;
    const extra = it.rarity ? ` · <span class="rar-${it.rarity}">${RARITY[it.rarity]}: ${bonusText(it)}</span>` : '';
    if (it.slot === 'wing') {
      const pct = (v) => Math.round((v + RULES.wingPerLevel * effLevel(upLevel(id))) * 100);
      return `Phòng thủ +${it.def}${b ? ` <span class="up">+${b}</span>` : ''} · Sát thương +${pct(it.dmg)}% · Nhận sát thương −${pct(it.absorb)}% · ${CLASSES[it.cls].name}`;
    }
    if (it.atk) return `Tấn công +${it.atk}${b ? ` <span class="up">+${b}</span>` : ''}${extra}`;
    if (it.def) return `Phòng thủ +${it.def}${b ? ` <span class="up">+${b}</span>` : ''}${extra}`;
    if (it.heal_pct) return `Hồi ${Math.round(it.heal_pct * 100)}% máu tối đa`;
    if (it.mana_pct) return `Hồi ${Math.round(it.mana_pct * 100)}% MP tối đa`;
    return '';
  }

  // Bảng nhân vật theo bố cục MU Web (charsheet): tên, lớp · cấp, EXP, 4 chỉ số với nút [+]
  // (bấm nhiều lần gom thành một lệnh `alloc`), điểm còn, rồi chỉ số chiến đấu do server tính.
  function viewHero() {
    const d = P.view.derived, c = CLASSES[P.cls];
    const free = P.points - allocPendingTotal();
    const need = P.view.xpToNext;
    // Phase 13: phần cộng thêm (đồ hiếm cộng chỉ số; thú cưng + món ăn cộng %)
    const ex = P.view.extra || {};
    const pc = (v) => (v ? ` <span class="up" title="Thú cưng + món ăn">+${Math.round(v * 100)}%</span>` : '');
    const kv = (k, v, cls) => `<div class="kv"><span>${k}</span><span class="num ${cls || ''}">${v}</span></div>`;
    const stat = (k) => {
      const [n, hint] = STAT_INFO[k], pend = allocPending[k] || 0;
      return `<div class="statrow" title="${esc(hint)}">
        <span>${n}</span>
        <span class="num">${P.stats[k]}${pend ? `<span class="pending">+${pend}</span>` : ''}${ex.gear && ex.gear[k] ? ` <span class="up" title="Đồ hiếm cộng thêm">+${ex.gear[k]}</span>` : ''}</span>
        <button class="btn" data-act="alloc-add" data-stat="${k}" ${free > 0 ? '' : 'disabled'} aria-label="Cộng 1 điểm ${n}">+</button>
      </div>`;
    };
    return `
      <div class="card charsheet" data-panel="character">
        <h3 class="panel-title">Nhân vật</h3>
        <div>${P.title ? `<span class="title-tag">${esc(achTitle(P.title))}</span>` : ''}<h2 class="display">${esc(P.name)}</h2>
          <div class="small muted">${c.name} · ${P.rebirths ? `Chuyển sinh ${P.rebirths} · ` : ''}Cấp ${P.level}</div>
          <button class="btn small-btn" data-act="profile" data-uid="${Net.userId}">📜 Hồ sơ</button></div>
        <hr class="sep">
        ${kv('EXP', P.level >= RULES.maxLevel ? 'Cấp tối đa' : `${fmt(P.xp)} / ${fmt(need)}`)}
        <hr class="sep">
        ${Object.keys(STAT_INFO).map(stat).join('')}
        ${kv('Điểm còn', free, free > 0 ? 'free' : '')}
        <p class="small muted">Mỗi lần lên cấp nhận ${c.points} điểm. Điểm đã cộng không gỡ được.</p>
        <hr class="sep">
        ${kv('Tấn công', `${fmt(d.atkMin)} ~ ${fmt(d.atkMax)}${pc(ex.atk)}`)}
        ${kv('Trúng quái cùng cấp', `${Math.round(d.hitRate * 100)}%`)}
        ${kv('Phòng thủ', `${fmt(d.def)}${pc(ex.def)}`)}
        ${kv('Chí mạng', `${Math.round(d.crit * 100)}% ×${d.critMult.toFixed(2)}`)}
        ${kv('Né đòn', `${Math.round(d.dodge * 100)}%`)}
        ${d.wingDmg ? kv('Cánh', `+${Math.round(d.wingDmg * 100)}% sát thương · −${Math.round(d.wingAbsorb * 100)}% nhận`) : ''}
        ${kv('Máu', `${fmt(P.hp)} / ${fmt(d.maxHp)}${pc(ex.hp)}`)}
        ${kv('MP', `${fmt(P.mp || 0)} / ${fmt(d.maxMp)}`)}
        ${P.food ? kv('Món ăn', `${esc(ITEMS[P.food.id].name)} · còn ${P.food.left} trận`) : ''}
      </div>`;
  }

  // Cộng điểm gom lệnh (như MU Web `alloc.ts`): mỗi lần bấm [+] cộng 1 điểm chờ, 200 ms sau lần bấm
  // cuối mới gửi một lệnh `alloc {stat, n}` cho mỗi chỉ số. Không vượt số điểm còn.
  let allocPending = {};
  let allocTimer = null;
  const allocPendingTotal = () => Object.values(allocPending).reduce((a, b) => a + b, 0);
  function allocAdd(stat) {
    const next = P && L.allocAdd(allocPending, stat, P.points);
    if (!next) return;
    allocPending = next;
    clearTimeout(allocTimer);
    allocTimer = setTimeout(allocFlush, 200);
    render();
  }
  async function allocFlush() {
    const pend = allocPending;
    allocPending = {};
    for (const cmd of L.allocBatches(pend)) {
      while (busy) await new Promise((r) => setTimeout(r, 50)); // đợi lệnh khác xong, không làm mất điểm
      await sendCommand(cmd);
    }
  }

  // ---------- Khác ----------
  // Các phần không thuộc Nhân vật / Túi đồ gom về đây: toàn bộ tab Hành trình cũ (hồi máu, hành trình
  // diệt rồng, bang, đấu trường, sổ tay quái, trùm thế giới, xếp hạng, thành tích, âm thanh, dữ liệu),
  // rồi thú cưng, kỹ năng, danh hiệu, thành tựu;
  // anh quyết sau giữ hay bỏ từng phần.
  function viewSkills() {
    const c = CLASSES[P.cls];
    return `
      <div class="card"><h3>Kỹ năng</h3><div class="list">
        ${c.skills.map((k) => `<div class="item ${k.level > P.level ? 'locked' : ''}">${icon(k.icon, 'lg')}<div class="grow">
          <div class="name">${k.name}${k.level > P.level ? ` <span class="small" style="color:var(--bad)">· mở ở cấp ${k.level}</span>` : ''}</div>
          <div class="small muted">${k.desc} Tốn ${skillMp(k)} MP, hồi chiêu ${k.cooldown} lượt.</div></div></div>`).join('')}
      </div></div>`;
  }

  // ---------- Menu ----------
  const MENU = [
    ['quests', 'scroll-unfurled', 'Nhiệm vụ'],
    ['journey', 'campfire', 'Hành trình'],
    ['arena', 'crossed-swords', 'Đấu trường'],
    ['board', 'laurels', 'Xếp hạng'],
    ['guild', 'hill-fort', 'Bang hội'],
    ['stats', 'trophy', 'Thành tựu'],
    ['pets', 'forest', 'Thú cưng'],
    ['skills', 'sword-spin', 'Kỹ năng'],
    ['bestiary', 'skull-crossed-bones', 'Sổ quái'],
    ['library', 'open-book', 'Thư viện'],
    ['tienlen', 'card-fan', 'Tiến Lên'],
    ['settings', 'speaker', 'Cài đặt'],
  ];
  let menuSec = null; // mục Menu đang mở (null: lưới biểu tượng)
  const onMenu = (sec) => tab === 'menu' && menuSec === sec;
  const MENU_VIEW = { quests: () => viewQuests(), journey: () => viewJourney(), arena: () => viewArena(), board: () => viewBoard(), guild: () => viewGuildCard(), stats: () => viewStats(), pets: () => viewPets(), skills: () => viewSkills(), bestiary: () => viewBestiary(), library: () => viewLibrary(), settings: () => viewSettings(), admin: () => viewAdmin() };
  function viewMenu() {
    const items = MENU.concat(Net.isAdmin ? [['admin', 'crowned-skull', 'Quản trị']] : []);
    if (menuSec && MENU_VIEW[menuSec]) {
      const it = items.find((x) => x[0] === menuSec);
      return `<div class="row menu-head"><button class="btn" data-act="menu-back">‹ Menu</button><h2 class="display grow">${it ? it[2] : ''}</h2></div>${MENU_VIEW[menuSec]()}`;
    }
    return `<h2 class="display">Menu</h2><div class="menu-grid">${items.map(([id, ic, label]) => `<button class="menu-item" data-menu="${id}">${icon(ic, 'lg')}<span>${label}</span></button>`).join('')}</div>`;
  }

  // ---------- Chọn bản đồ (Phase 15a, U2) ----------
  // Mọi bản đồ xếp yếu → mạnh (cấp quái thấp nhất). Tới được: Làng, Nhà, vùng đã mở, bản đồ phụ đã đi qua cổng.
  let travelQ = '';
  const TRAVEL = RULES.travel || { base: 20, perLevel: 4, free: ['village', 'home'] };
  const travelCost = (m) => (TRAVEL.free.includes(m.id) ? 0 : TRAVEL.base + TRAVEL.perLevel * (m.min || 0));
  function travelOpen(id) {
    const w = WORLD.maps[id];
    if (!w) return false;
    if (TRAVEL.free.includes(id)) return true;
    if (w.side) return (P.visited || []).includes(id);
    if (w.zone != null) return !!P.view.unlocked[w.zone];
    return id !== 'tower';
  }
  async function travelTo(id) {
    await sendCommand({ act: 'travel', to: id });
    if (P && P.pos.map === id) { Sound.play('portal'); goTab('map'); }
  }
  function viewTravel() {
    const home = { id: 'home', name: WORLD.maps.home ? WORLD.maps.home.name : 'Nhà', min: null, max: null, zone: null };
    const all = [home].concat(LIB.maps).filter((m) => m.id !== 'tower');
    return `<div class="card"><div class="row"><h3 class="grow">🗺 Chọn bản đồ</h3><span class="small muted">phím M</span></div>
      <p class="small muted">Dịch chuyển tốn ${TRAVEL.base} + ${TRAVEL.perLevel} × cấp quái thấp nhất (Làng, Nhà miễn phí). Bản đồ phụ: đi qua cổng một lần để mở. Đá dịch chuyển vẫn miễn phí.</p>
      <input type="search" id="travel-q" class="lib-q" placeholder="Tìm bản đồ…" value="${esc(travelQ)}" autocomplete="off" aria-label="Tìm bản đồ">
      <div id="travel-list">${travelList(all)}</div></div>`;
  }
  function travelList(all) {
    all = all || [{ id: 'home', name: (WORLD.maps.home || {}).name || 'Nhà', min: null }].concat(LIB.maps).filter((m) => m.id !== 'tower');
    const rows = all.filter((m) => L.nameMatch([m.name, trn(m.name)], travelQ)).sort((a, b) => (a.min || 0) - (b.min || 0) || (a.max || 0) - (b.max || 0));
    return `<div class="list">${rows.map((m) => {
      const here = P.pos.map === m.id, open = travelOpen(m.id), cost = travelCost(m);
      const lv = m.min ? (m.min === m.max ? `Cấp ${m.min}` : `Cấp ${m.min}–${m.max}`) : 'Không có quái';
      const btn = here ? '<span class="tag">Đang ở</span>'
        : !open ? `<span class="tag" title="${WORLD.maps[m.id] && WORLD.maps[m.id].side ? 'Đi qua cổng một lần để mở' : 'Vùng chưa mở'}">🔒</span>`
        : `<button class="btn small-btn ${P.gold >= cost ? 'primary' : ''}" data-act="travel" data-to="${m.id}" ${P.gold >= cost ? '' : 'disabled'}>${cost ? `${icon('two-coins')}${fmt(cost)}` : 'Miễn phí'}</button>`;
      return `<div class="item travel-row ${open ? '' : 'locked'}"><div class="grow"><div class="name">${esc(m.name)}</div><div class="small muted">${lv}${m.zone ? ` · ${esc(m.zone)}` : ''}</div></div>${btn}</div>`;
    }).join('')}</div>`;
  }

  // ---------- Thư viện (Phase 14) ----------
  // Dữ liệu `GAME_DATA.LIBRARY` (server sinh từ dữ liệu game). Gõ tìm chỉ vẽ lại phần kết quả để ô nhập không mất chữ.
  const LIB = window.GAME_DATA.LIBRARY || { maps: [], monsters: [], items: [] };
  let libUi = { tab: 'maps', q: '', open: null };
  const SLOT_NAME = { weapon: 'Vũ khí', armor: 'Giáp', shield: 'Khiên', wing: 'Cánh', potion: 'Bình', material: 'Nguyên liệu', food: 'Món ăn', fish: 'Cá', relic: 'Bảo vật' };
  const trn = (t) => (window.I18N ? window.I18N.tr(t) : t);
  const libMap = (id) => LIB.maps.find((m) => m.id === id);
  const libMon = (id) => LIB.monsters.find((m) => m.id === id);
  const go = (tab, name) => `<button class="lib-link" data-act="lib-go" data-tab2="${tab}" data-q="${esc(name)}">${esc(name)}</button>`;
  function viewLibrary() {
    const tabs = [['maps', 'Bản đồ', LIB.maps.length], ['monsters', 'Quái', LIB.monsters.length], ['items', 'Vật phẩm', LIB.items.length]];
    return `<div class="card">
      <div class="seg" id="lib-tabs">${tabs.map(([k, l, n]) => `<button class="btn ${libUi.tab === k ? 'primary' : ''}" data-act="lib-tab" data-tab2="${k}">${l} <span class="small">${n}</span></button>`).join('')}</div>
      <input type="search" id="lib-q" class="lib-q" placeholder="Tìm theo tên (không cần dấu)…" value="${esc(libUi.q)}" autocomplete="off" aria-label="Tìm trong thư viện">
      <div id="lib-results">${libResults()}</div></div>`;
  }
  function libResults() {
    const list = LIB[libUi.tab].filter((x) => L.nameMatch([x.name, trn(x.name)], libUi.q));
    if (!list.length) return '<p class="small muted">Không tìm thấy.</p>';
    const row = libUi.tab === 'maps' ? libMapRow : libUi.tab === 'monsters' ? libMonRow : libItemRow;
    return `<div class="list">${list.slice(0, 120).map(row).join('')}</div>${list.length > 120 ? `<p class="small muted">Còn ${list.length - 120} kết quả, gõ thêm để lọc.</p>` : ''}`;
  }
  const libHead = (key, left, title, sub) => `<button class="item lib-row" data-act="lib-open" data-key="${esc(key)}" aria-expanded="${libUi.open === key}">${left}<div class="grow"><div class="name">${title}</div><div class="small muted">${sub}</div></div><span class="small muted">${libUi.open === key ? '▾' : '▸'}</span></button>`;
  const libLine = (k, v) => (v ? `<div class="kv"><span>${k}</span><span>${v}</span></div>` : '');
  function libMapRow(m) {
    const key = 'map:' + m.id;
    const lv = m.min ? (m.min === m.max ? `Cấp ${m.min}` : `Cấp ${m.min}–${m.max}`) : 'Không có quái';
    const head = libHead(key, icon(m.zone ? 'forest' : 'village', 'lg'), esc(m.name), `${m.zone ? esc(m.zone) + ' · ' : ''}${lv}`);
    if (libUi.open !== key) return head;
    const mons = m.monsters.map((id) => libMon(id)).filter(Boolean);
    const boss = m.boss && libMon(m.boss);
    return head + `<div class="lib-detail">
      ${libLine('Quái', mons.map((x) => `${go('monsters', x.name)} <span class="muted">(${x.level})</span>`).join(', '))}
      ${libLine('Trùm', boss ? `${go('monsters', boss.name)} <span class="muted">(${boss.level})</span>` : '')}
      ${libLine('Trùm thế giới', m.world_boss ? 'Cổ Long xuất hiện ở đây' : '')}
      ${libLine('Cổng tới', m.to.map((id) => libMap(id)).filter(Boolean).map((x) => go('maps', x.name)).join(', '))}
      ${libLine('NPC', m.npcs.map(esc).join(', '))}
      ${libLine('Thu thập', m.gather.map((id) => ITEMS[id] ? go('items', ITEMS[id].name) : esc(id)).join(', '))}
    </div>`;
  }
  function libMonRow(m) {
    const key = 'mon:' + m.id;
    const head = libHead(key, sprite(m.id, 'sm', m.name), `${m.boss ? '👑 ' : ''}${esc(m.name)}`, `Cấp ${m.level} · ${esc(m.zone)}`);
    if (libUi.open !== key) return head;
    return head + `<div class="lib-detail">
      <div class="lib-stats"><span>❤ ${fmt(m.hp)}</span><span>⚔ ${fmt(m.atk)}</span><span>🛡 ${fmt(m.def)}</span><span>⭐ ${fmt(m.xp)}</span><span>${icon('two-coins')} ~${fmt(m.gold)}</span></div>
      ${libLine('Đòn đặc biệt', m.special ? `${esc(m.special.name)} mỗi ${m.special.every} lượt` : '')}
      ${libLine('Khi đánh trúng', m.on_hit ? `${Math.round(m.on_hit.chance * 100)}% gây ${esc((EFFECTS[m.on_hit.id] || [0, m.on_hit.id])[1])}` : '')}
      ${libLine('Xuất hiện ở', m.where.map((n) => go('maps', n)).join(', '))}
      ${libLine('Có thể rơi', m.drops.map((id) => ITEMS[id] ? go('items', ITEMS[id].name) : esc(id)).join(', '))}
    </div>`;
  }
  function libItemRow(x) {
    const key = 'item:' + x.id, it = ITEMS[x.id] || x;
    const head = libHead(key, itemIcon(it), esc(x.name), `${SLOT_NAME[x.slot] || esc(x.slot)}${x.level ? ` · cần cấp ${x.level}` : ''}${x.cls && CLASSES[x.cls] ? ` · ${CLASSES[x.cls].name}` : ''}`);
    if (libUi.open !== key) return head;
    return head + `<div class="lib-detail">
      ${libLine('Chỉ số', itemStat(it))}
      ${libLine('Giá', x.price ? `${fmt(x.price)} vàng` : '')}
      ${libLine('Có được từ', x.sources.length ? x.sources.map(esc).join('<br>') : 'Chưa có nguồn (đồ đặc biệt)')}
    </div>`;
  }
  function libRefresh() { const r = $('#lib-results'); if (r) r.innerHTML = libResults(); }

  // ---------- Thú cưng ----------
  // Thú bán ở cửa hàng hoặc quái đã thuần phục ("tame:<id quái>")
  const MONSTER_BY_ID = {};
  ZONES.forEach((z) => z.monsters.forEach((m) => { MONSTER_BY_ID[m.id] = m; }));
  const tamePrice = (m) => L.tamePrice(m, RULES.tamePrice, RULES.tamePricePerLevel);
  function petInfo(id) {
    if (id && id.startsWith('tame:')) {
      const m = MONSTER_BY_ID[id.slice(5)];
      return m && { id, name: m.name + ' (thuần)', desc: `Tấn công +${Math.round(RULES.tameBonus * 100)}%.`, sprite: 'monsters/' + m.id };
    }
    const pt = PETS.find((x) => x.id === id);
    return pt && { ...pt, sprite: 'pets/' + pt.id };
  }
  // Cấp thú: lên cấp theo số trận thắng khi được dắt (HacLong.Game.Pets)
  const petLevel = (id) => L.petLevel((P.pet_xp && P.pet_xp[id]) || 0, RULES.petXpCoef, RULES.petMaxLevel);
  const TAME_SKILL = { id: 'rend', name: 'Cắn Xé', desc: 'Cú cắn gây gấp đôi sát thương.' };
  function petSkill(id) {
    if (id.startsWith('tame:')) return TAME_SKILL;
    const pt = PETS.find((x) => x.id === id);
    return pt && pt.skill;
  }
  function viewPets() {
    const owned = (P.pets || []).map(petInfo).filter(Boolean);
    if (!owned.length) return `<div class="card"><h3>Thú cưng</h3><p class="small muted">Chưa có thú cưng. Gặp Người Nuôi Thú ở góc dưới bên phải Làng.</p></div>`;
    return `<div class="card"><h3>Thú cưng</h3><p class="small muted">Thú đi theo thỉnh thoảng cắn thêm một đòn trong trận. Thắng trận khi dắt theo thì thú lên cấp: mạnh hơn, hay cắn hơn; cấp ${RULES.petSkillLevel} học kỹ năng riêng.</p><div class="list">${owned.map((pt) => {
      const L = petLevel(pt.id), sk = petSkill(pt.id), learned = L.lv >= RULES.petSkillLevel;
      const pct = L.next ? Math.round(((L.xp - L.from) / (L.next - L.from)) * 100) : 100;
      return `<div class="item"><img class="sprite" src="${asset(pt.sprite + '.png')}" alt=""><div class="grow">
        <div class="name">${esc(pt.name)} <span class="small num" style="color:var(--gold)">· Cấp ${L.lv}</span></div>
        <div class="small muted">${esc(pt.desc)}${L.lv > 1 ? ` (×${(1 + (L.lv - 1) * 0.1).toFixed(1)})` : ''}</div>
        <div class="bar xp" style="height:6px;margin:4px 0" title="${L.next ? `${L.xp}/${L.next} trận` : 'Cấp tối đa'}"><i style="width:${pct}%"></i></div>
        <div class="small muted">${L.next ? `${fmt(L.xp)}/${fmt(L.next)} trận thắng` : 'Cấp tối đa'}</div>
        ${sk ? `<div class="small" style="${learned ? 'color:var(--good)' : ''}">${learned ? '✨' : '🔒'} ${esc(sk.name)}: ${esc(sk.desc)}${learned ? '' : ` (cấp ${RULES.petSkillLevel})`}</div>` : ''}</div>
      ${P.pet === pt.id ? '<button class="btn" data-act="pet_choose" data-id="">Để ở nhà</button>' : `<button class="btn primary" data-act="pet_choose" data-id="${pt.id}">Dắt theo</button>`}</div>`;
    }).join('')}</div></div>`;
  }

  // ---------- Trang trí nhà ----------
  function viewDecorButton() {
    if (P.pos.map !== 'home' || decor.on) return '';
    return `<div class="fish-ui idle"><button class="btn" data-act="decor-on">${icon('village')} Trang trí</button></div>`;
  }

  function viewDecorPanel() {
    if (P.pos.map !== 'home' || !decor.on) return '';
    const stock = Object.entries(P.furniture || {}).filter(([, n]) => n > 0);
    if (decor.pick && !(P.furniture || {})[decor.pick]) decor.pick = null;
    const name = (id) => (FURNITURE.find((f) => f.id === id) || { name: id }).name;
    return `<div class="card decor-panel">
      <div class="row"><h3 class="grow">Trang trí nhà</h3><span class="tag gold num">Tiện nghi ${P.view.comfort}</span><button class="btn" data-act="decor-off">Xong</button></div>
      <p class="small muted">${decor.pick ? `Chạm vào ô trống để đặt <b>${esc(name(decor.pick))}</b>.` : 'Chọn một món trong kho rồi chạm vào ô để đặt. Chạm vào đồ đã đặt để cất vào kho.'}</p>
      ${stock.length ? `<div class="chips">${stock.map(([id, n]) => `<button class="chip ${decor.pick === id ? 'on' : ''}" data-act="decor-pick" data-id="${id}"><img class="ic px" src="${asset('decor/' + id + '.png')}" alt=""> ${esc(name(id))}${n > 1 ? ` ×${n}` : ''}</button>`).join('')}</div>`
        : '<p class="small muted">Kho trống. Mua đồ trang trí ở Thợ Mộc trong Làng.</p>'}
    </div>`;
  }

  async function decorTap(x, y) {
    const placed = (P.decor || []).find((d) => d.x === x && d.y === y);
    if (placed) return sendCommand({ act: 'decor_take', x, y });
    if (!decor.pick) { toast('Chọn một món trong kho trước.', true); return; }
    await sendCommand({ act: 'decor_place', id: decor.pick, x, y });
  }

  // ---------- Thành tựu, danh hiệu ----------
  const achTitle = (id) => { const a = ACHIEVEMENTS.find((x) => x.id === id); return a ? a.title : ''; };

  function viewAchievements() {
    const prog = Object.fromEntries((P.view.achievements || []).map((a) => [a.id, a]));
    const done = ACHIEVEMENTS.filter((a) => prog[a.id] && prog[a.id].done);
    const titles = done.filter((a) => a.title);
    const titleCard = `<div class="card">
      <div class="row">${icon('laurels', 'lg')}<div class="grow"><h3>Danh hiệu</h3>
        <p class="small muted">Hiện cạnh tên bạn trong chat và bảng xếp hạng.</p></div></div>
      ${titles.length ? `<div class="chips">${titles.map((a) => `<button class="chip ${P.title === a.id ? 'on' : ''}" data-act="title_set" data-id="${P.title === a.id ? '' : a.id}" aria-pressed="${P.title === a.id}">${esc(a.title)}</button>`).join('')}</div>`
        : '<p class="small muted">Chưa có danh hiệu nào. Đạt thành tựu để nhận.</p>'}
    </div>`;
    const list = ACHIEVEMENTS.map((a) => {
      const pr = prog[a.id] || { done: false, have: 0 };
      const pct = Math.min(100, Math.round((pr.have / a.goal) * 100));
      return `<div class="item ach ${pr.done ? 'done' : ''}">${icon('medal', 'lg')}
        <div class="grow"><div class="name">${esc(a.name)}${a.title ? ` <span class="small" style="color:var(--gold)">· danh hiệu “${esc(a.title)}”</span>` : ''}</div>
          <div class="small muted">${esc(a.desc)}</div>
          ${pr.done ? '' : a.goal > 1 ? `<div class="mini-bar"><i style="width:${pct}%"></i></div><div class="small muted num">${fmt(pr.have)} / ${fmt(a.goal)}</div>` : ''}
        </div>${pr.done ? '<span class="tag good">Đã đạt</span>' : ''}</div>`;
    }).join('');
    return `${titleCard}
      <div class="card"><div class="row"><h3 class="grow">Thành tựu</h3><span class="tag gold num">${done.length}/${ACHIEVEMENTS.length}</span></div>
        <div class="list">${list}</div></div>`;
  }

  // ---------- Túi đồ ----------
  function compare(it, id) {
    const curId = P.equip[it.slot];
    // như bot mô phỏng: mỗi điểm chỉ số cộng thêm tính bằng 2 tấn công/phòng thủ
    const v = (x) => { const t = x && itemOf(x); return t ? (t.atk || 0) + (t.def || 0) + (P.view.bonus[x] || 0) + 2 * Object.values(t.bonus || {}).reduce((a, b) => a + b, 0) : 0; };
    const diff = v(id) - v(curId);
    return diff > 0 ? `<span class="up">▲ ${diff}</span>` : '';
  }

  // Túi đồ theo bố cục MU Web: lưới trang bị 3×4 (10 ô, ô chưa có trong Hắc Long hiện 🔒),
  // lưới túi 8 cột tự xếp (Hắc Long không lưu vị trí ô), bấm ô xem chi tiết + nút, kéo thả để
  // mặc / tháo (chuột), thanh tóm tắt dưới cùng.
  const EQUIP_GRID = [
    [null, 'helm', null],
    ['weapon', 'armor', 'shield'],
    ['gloves', 'pants', 'boots'],
    ['ring1', 'wing', 'ring2'],
  ];
  const SLOT_LABEL = { helm: 'Mũ', weapon: 'Vũ khí', armor: 'Giáp', shield: 'Khiên', gloves: 'Găng', pants: 'Quần', boots: 'Giày', ring1: 'Nhẫn', wing: 'Cánh', ring2: 'Nhẫn' };
  const SLOT_OPEN = ['weapon', 'armor', 'shield', 'wing'];
  // ô tháo ra được (vũ khí, giáp chỉ thay bằng món khác)
  const SLOT_REMOVABLE = ['shield', 'wing'];
  const BAG_COLUMNS = 8;
  const BAG_MIN_CELLS = 32;

  // Đồ trong túi theo thứ tự: trang bị (đồ hiếm trước) → bình máu → món ăn → nguyên liệu
  function bagItems() {
    const ids = Object.keys(P.inv).filter((id) => P.inv[id] > 0 && ITEMS[id]);
    const by = (slot) => ids.filter((id) => ITEMS[id].slot === slot);
    const gear = bagGear().concat(ids.filter((id) => SLOT_OPEN.includes(ITEMS[id].slot)));
    return gear.concat(by('potion'), by('food'), by('material'));
  }
  const potionCount = () => Object.keys(P.inv).filter((id) => ITEMS[id] && ITEMS[id].heal_pct).reduce((a, id) => a + P.inv[id], 0);

  function cellIcon(it, level) {
    const own = ownIcon(it, level);
    if (own) return `<img src="${own}" alt="" draggable="false" class="own">`;
    return it.sprite ? `<img src="${asset(it.sprite + '.png')}" alt="" draggable="false" class="px">` : `<img src="${asset('icons/' + it.icon + '.svg')}" alt="" draggable="false">`;
  }

  function viewBag() {
    const items = bagItems();
    const cells = Math.max(BAG_MIN_CELLS, Math.ceil((items.length + 1) / BAG_COLUMNS) * BAG_COLUMNS);
    const equip = EQUIP_GRID.flat().map((slot) => {
      if (!slot) return '<span class="slot none"></span>';
      const id = SLOT_OPEN.includes(slot) ? P.equip[slot] : null, it = id ? itemOf(id) : null;
      const locked = !SLOT_OPEN.includes(slot);
      return `<button class="slot${it ? '' : ' empty'}${locked ? ' locked' : ''}${it && it.rarity ? ` rar-b-${it.rarity}` : ''}${it ? upClass(upLevel(id)) : ''}" data-act="${it ? 'slot-tip' : 'noop'}" data-slot="${slot}"
          ${locked ? 'title="Sắp có" aria-disabled="true"' : `data-drop-slot="${slot}"`} ${it && SLOT_REMOVABLE.includes(slot) ? `draggable="true" data-drag-equip="${slot}"` : ''}>
        ${it ? cellIcon(it, upLevel(id)) : ''}${it && upLevel(id) ? `<span class="lvl">+${upLevel(id)}</span>` : ''}${it && it.locked ? '<span class="lockb">🔒</span>' : ''}
        <span class="lbl">${SLOT_LABEL[slot]}</span>
      </button>`;
    }).join('');
    const bag = Array.from({ length: cells }, (_, i) => {
      const id = items[i];
      if (!id) return '<span class="cell empty"></span>';
      const it = itemOf(id), n = isGear(id) ? 1 : P.inv[id];
      const wearable = SLOT_OPEN.includes(it.slot);
      return `<button class="cell${it.rarity ? ` rar-b-${it.rarity}` : ''}${upClass(upLevel(id))}${(it.level && P.level < it.level) || (it.cls && it.cls !== P.cls) ? ' low' : ''}" data-act="bag-tip" data-id="${esc(id)}"
          ${wearable ? `draggable="true" data-drag-id="${esc(id)}"` : ''} aria-label="${esc(it.name)}">
        ${cellIcon(it, upLevel(id))}${n > 1 ? `<span class="qty num">${n}</span>` : ''}${upLevel(id) ? `<span class="lvl">+${upLevel(id)}</span>` : ''}${it.locked ? '<span class="lockb">🔒</span>' : ''}
      </button>`;
    }).join('');
    return `
      <div class="card inv" data-panel="inventory">
        <h3 class="panel-title">Túi đồ</h3>
        <div class="equip">
          <div class="small muted" style="text-align:center">Trang bị đang mặc</div>
          <div class="grid3">${equip}</div>
        </div>
        <div class="bag-head">Túi đồ</div>
        <div class="bag" data-drop-bag style="--cols:${BAG_COLUMNS}">${bag}</div>
        ${items.length ? '' : '<p class="small muted emptytext">Túi trống</p>'}
        <div class="bag-bottom">
          <div class="row"><span class="gold">${icon('two-coins')}${fmt(P.gold)}</span><span class="num">Đồ hiếm ${bagGear().length}/${RULES.gearBag}</span></div>
          <div class="row"><span>${icon('health-potion')} Bình máu ×<b class="num">${potionCount()}</b></span><span class="num">${items.length} món</span></div>
          ${foodNow()}
          <p class="small muted">Muốn bán đồ, hãy gặp Thợ Rèn hoặc Bà Lang trong Làng.</p>
        </div>
      </div>`;
  }

  // ---------- Bảng chi tiết món đồ (tooltip kiểu MU Web) ----------
  let tipAt = null; // { id?, slot?, x, y }
  let forgePick = null; // món trong túi chọn để ép ở Thợ Rèn (nút "Ép" trong tooltip)
  // dòng Ngọc Sinh Mệnh của món đồ
  const lifeLine = (it) => it.opt ? `<div class="small" style="color:var(--good)">💚 Ngọc Sinh Mệnh: +${it.opt * RULES.life.per_line} ${it.slot === 'weapon' ? 'tấn công' : 'phòng thủ'} (${it.opt}/${RULES.life.max_lines} dòng)</div>` : '';
  function hideTip() {
    tipAt = null;
    const el = document.getElementById('itemtip');
    if (el) el.remove();
  }
  function showTip(at) {
    hideTip();
    const id = at.slot ? P.equip[at.slot] : at.id;
    const it = id && itemOf(id);
    if (!it) return;
    tipAt = at;
    const d = P.view.derived;
    const low = (it.level && P.level < it.level) || (it.cls && it.cls !== P.cls);
    const wearable = SLOT_OPEN.includes(it.slot);
    const desc = ['material', 'food'].includes(it.slot) ? esc(it.desc || '') : itemStat(it, id);
    // khóa đồ: không bán / rao chợ / giao dịch / bỏ vào máy ghép được
    const lockBtn = wearable ? `<button class="btn" data-act="lock" data-id="${esc(id)}" data-on="${it.locked ? '0' : '1'}">${it.locked ? 'Mở khóa' : '🔒 Khóa'}</button>` : '';
    const btns = at.slot
      ? (SLOT_REMOVABLE.includes(at.slot) ? `<button class="btn" data-act="unequip" data-slot="${at.slot}">Tháo</button>` : '<span class="small muted">Mặc món khác cùng loại để thay.</span>') + lockBtn
      : wearable ? `<button class="btn primary" data-act="equip" data-id="${esc(id)}" ${low ? 'disabled' : ''}>Trang bị</button>${lockBtn}`
      : it.slot === 'potion' ? `<button class="btn primary" data-act="use" data-id="${esc(id)}" ${P.hp >= d.maxHp ? 'disabled' : ''}>Dùng</button>`
      : it.slot === 'food' ? `<button class="btn primary" data-act="use" data-id="${esc(id)}">Ăn</button>` : '';
    const n = isGear(id) ? 1 : P.inv[id] || 0;
    // ép món trong túi (mang tới Thợ Rèn), vứt món trong túi
    const forgeBtn = !at.slot && P.view.forgeBag[id] ? `<button class="btn" data-act="forge-pick" data-id="${esc(id)}">${icon('anvil')}Ép</button>` : '';
    const dropBtn = !at.slot && !it.locked ? `<button class="btn danger" data-act="discard" data-id="${esc(id)}" data-n="${n}" data-name="${esc(itemName(id))}">Vứt</button>` : '';
    const el = document.createElement('div');
    el.id = 'itemtip';
    el.className = 'itemtip';
    el.setAttribute('role', 'dialog');
    el.innerHTML = `
      <div class="big">${itemIcon(it, it.rarity, upLevel(id))}</div>
      <b>${itemName(id)}${!at.slot && n > 1 ? ` <span class="muted num">×${n}</span>` : ''}</b>
      ${desc ? `<div class="small">${desc}</div>` : ''}
      ${!at.slot && wearable ? `<div class="small">${compare(it, id) || '<span class="muted">Không mạnh hơn đồ đang mặc</span>'}</div>` : ''}
      ${it.level ? `<div class="small ${it.level > P.level ? 'bad' : 'muted'}">Cần cấp ${it.level}</div>` : ''}
      ${lifeLine(it)}
      ${it.locked ? '<div class="small muted">🔒 Đã khóa: không bán, rao chợ, giao dịch, vứt, bỏ vào máy ghép được.</div>' : ''}
      ${at.slot ? '<div class="small" style="color:var(--good)">Đang mặc</div>' : ''}
      <div class="btns">${btns}${forgeBtn}${dropBtn}</div>`;
    document.body.appendChild(el);
    // đặt cạnh chỗ bấm, không tràn khỏi màn hình
    const r = el.getBoundingClientRect(), pad = 8;
    const left = Math.min(Math.max(pad, at.x + 12), innerWidth - r.width - pad);
    const top = at.y + 12 + r.height > innerHeight - pad ? Math.max(pad, at.y - r.height - 12) : at.y + 12;
    el.style.left = left + 'px';
    el.style.top = top + 'px';
  }

  // Kéo thả bằng chuột: kéo đồ trong túi lên ô trang bị để mặc, kéo khiên đang mặc về túi để tháo.
  let dragging = null; // { id } | { equip: 'shield' | 'wing' }
  function onDragStart(e) {
    const t = e.target.closest('[data-drag-id], [data-drag-equip]');
    if (!t) return;
    hideTip();
    dragging = t.dataset.dragId ? { id: t.dataset.dragId } : { equip: t.dataset.dragEquip };
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', t.dataset.dragId || t.dataset.dragEquip);
  }
  function dropTarget(e) {
    return dragging && e.target.closest(dragging.id ? '[data-drop-slot]' : '[data-drop-bag]');
  }
  function onDragOver(e) {
    const t = dropTarget(e);
    if (!t) return;
    e.preventDefault();
    document.querySelectorAll('.over').forEach((x) => x !== t && x.classList.remove('over'));
    t.classList.add('over');
  }
  function onDrop(e) {
    const t = dropTarget(e), from = dragging;
    dragging = null;
    document.querySelectorAll('.over').forEach((x) => x.classList.remove('over'));
    if (!t || !P) return;
    e.preventDefault();
    if (from.id) {
      const it = itemOf(from.id);
      if (!it || it.slot !== t.dataset.dropSlot) { toast(`Món này không mặc vào ô ${SLOT_LABEL[t.dataset.dropSlot]}.`, true); return; }
      sendCommand({ act: 'equip', id: from.id });
    } else if (SLOT_REMOVABLE.includes(from.equip)) {
      sendCommand({ act: 'unequip', slot: from.equip });
    }
  }

  // ---------- NPC ----------
  const npcData = () => WORLD.maps[npc.map].npcs.find((n) => n.id === npc.id);

  function shopRow(id) {
    const it = ITEMS[id], slot = it.slot;
    const low = it.level && P.level < it.level;
    const worn = P.equip[slot] === id;
    const owned = P.inv[id] || 0;
    const price = L.shopPrice(it, P.level, RULES.potionPricePerLevel);
    const poor = P.gold < price;
    return `<div class="item">
      ${itemIcon(it)}
      <div class="grow">
        <div class="name">${it.name}</div>
        <div class="small muted">${itemStat(it)} ${slot !== 'potion' ? compare(it, id) : ''}${low ? ` · <span style="color:var(--bad)">Cần cấp ${it.level}</span>` : ''}${worn ? ' · <span style="color:var(--good)">Đang dùng</span>' : ''}${owned ? ` · có ${owned}` : ''}</div>
      </div>
      ${slot === 'potion' ? `<button class="btn" data-act="buy5" data-id="${id}" ${P.gold < price * 5 ? 'disabled' : ''}>×5</button>` : ''}
      <button class="btn ${!low && !poor ? 'primary' : ''}" data-act="buy" data-id="${id}" ${low || poor ? 'disabled' : ''}>${icon('two-coins')}${fmt(price)}</button>
    </div>`;
  }

  // đồ chỉ số ngẫu nhiên trong túi (không đang mặc), hiếm trước
  const bagGear = () => Object.values(P.view.gear).filter((g) => !g.stored && !Object.values(P.equip).includes(g.uid))
    .sort((a, b) => b.rarity - a.rarity || (b.level || 0) - (a.level || 0)).map((g) => g.uid);

  function sellCard() {
    const ids = Object.keys(P.inv).filter((id) => P.inv[id] > 0).concat(bagGear());
    return `<div class="card"><h3>Bán đồ</h3>
      ${ids.length ? `<div class="list">${ids.map((id) => {
        const it = itemOf(id), n = isGear(id) ? 1 : P.inv[id];
        return `<div class="item">${itemIcon(it, it.rarity, upLevel(id))}<div class="grow"><div class="name">${itemName(id)}${n > 1 ? ` <span class="muted num">×${n}</span>` : ''}</div></div>
          ${it.locked ? '<span class="small muted">Đã khóa</span>' : `<button class="btn" data-act="sell" data-id="${id}" aria-label="Bán ${it.name}">Bán ${fmt(it.sell)}</button>`}</div>`;
      }).join('')}</div>` : '<p class="small muted">Túi trống. Đồ đang mặc không bán được.</p>'}
    </div>`;
  }

  // Thợ Rèn: +1 → +5 bằng quặng (chắc chắn), +6 → +11 bằng ngọc (có tỉ lệ, thất bại tụt cấp hoặc vỡ đồ).
  const RISK = { down: 'thất bại tụt 1 cấp', destroy: 'thất bại VỠ ĐỒ' };
  function forgeCard() {
    if (forgePick && !P.view.forgeBag[forgePick]) forgePick = null;
    const life = RULES.life, jewels = P.inv[life.jewel] || 0;
    const slots = [['weapon', 'Vũ khí'], ['armor', 'Giáp'], ['shield', 'Khiên'], ['wing', 'Cánh']]
      .map(([slot, label]) => [slot, label, P.view.forge[slot]]);
    if (forgePick) slots.unshift([null, 'Trong túi (đã chọn)', Object.assign({ id: forgePick }, P.view.forgeBag[forgePick])]);
    const rows = slots.map(([slot, label, f]) => {
      if (!f) return '';
      const it = itemOf(f.id), c = f.cost, opt = it.opt || 0;
      const target = slot ? `data-slot="${slot}"` : `data-id="${esc(f.id)}"`;
      const lifeBtn = opt < life.max_lines ? `<button class="btn" data-act="life" ${target} ${jewels ? '' : 'disabled'} title="${esc(ITEMS[life.jewel].name)}: ${Math.round(life.rate * 100)}%">💚 ${opt}/${life.max_lines}</button>` : `<span class="small" style="color:var(--good)">💚 ${opt}/${life.max_lines}</span>`;
      const need = c ? Object.entries(c.items) : [];
      const ok = c && P.gold >= c.gold && need.every(([id, n]) => (P.inv[id] || 0) >= n);
      const per = it.atk || it.def ? Math.max(1, Math.round((it.atk || it.def) * RULES.upgradeBonusPct)) : 0;
      const step = c ? per * (effLevel(f.level + 1) - effLevel(f.level)) : 0;
      const odds = c && c.rate < 1 ? ` · <b>${Math.round(c.rate * 100)}%</b>${c.fail ? `, <span style="color:var(--bad)">${RISK[c.fail]}</span>` : ''}` : '';
      return `<div class="item">${icon(it.icon, 'lg')}<div class="grow">
          <div class="small muted">${label}</div><div class="name">${itemName(f.id)}</div>
          ${c ? `<div class="small muted">Lên +${f.level + 1}: ${it.atk ? 'tấn công' : 'phòng thủ'} +${step}${slot === 'wing' ? `, +${Math.round(RULES.wingPerLevel * 100)}% sát thương / hấp thụ` : ''}${odds} · ${need.map(([id, n]) => `<span style="${(P.inv[id] || 0) >= n ? '' : 'color:var(--bad)'}">${ITEMS[id].name} ${Math.min(P.inv[id] || 0, n)}/${n}</span>`).join(' · ')}</div>`
            : '<div class="small" style="color:var(--gold)">Đã nâng tối đa</div>'}
        </div>
        ${c ? `<button class="btn ${ok ? (c.fail === 'destroy' ? 'danger' : 'primary') : ''}" data-act="upgrade" ${target} data-risk="${c.fail || ''}" data-name="${esc(it.name)} +${f.level}" ${ok ? '' : 'disabled'}>${icon('anvil')}${fmt(c.gold)}</button>` : ''}
        ${lifeBtn}
      </div>`;
    }).join('');
    const table = UPGRADE.steps.map((s) => `+${s.level}: ${ITEMS[s.jewel].name} ${Math.round(s.rate * 100)}%${s.fail ? ` (${RISK[s.fail]})` : ''}`).join(' · ');
    return `<div class="card"><h3>Ép đồ</h3>
      <p class="small muted">Mỗi cấp thêm ${Math.round(RULES.upgradeBonusPct * 100)}% chỉ số của món đồ; từ +${UPGRADE.double_from} mỗi cấp tính gấp đôi. +1 → +5 dùng quặng (đồ dưới cấp 17 dùng Quặng Sắt, cao hơn dùng Mithril), luôn thành công. Từ +6 dùng ngọc: ${table}. Ngọc và vàng mất cả khi thất bại. Cấp nâng theo từng món. Muốn ép đồ trong túi: bấm món đó trong túi rồi chọn Ép.</p>
      <p class="small muted">💚 ${esc(ITEMS[life.jewel].name)} (có ${jewels}): thêm một dòng +${life.per_line} tấn công (vũ khí) hoặc phòng thủ (giáp, khiên, cánh), tối đa ${life.max_lines} dòng; tỉ lệ ${Math.round(life.rate * 100)}%, thất bại mất một dòng.</p>
      <div class="list">${rows}</div></div>`;
  }

  // Tủ Đồ ở Nhà: cất / lấy đồ thường (theo loại) và đồ hiếm (theo món), mở rộng chỗ đồ hiếm bằng vàng.
  function wardrobeCard() {
    const st = P.view.storage;
    const row = (id, n, act, label) => {
      const it = itemOf(id);
      return `<div class="item">${itemIcon(it, it.rarity, upLevel(id))}<div class="grow"><div class="name">${itemName(id)}${n > 1 ? ` <span class="muted num">×${n}</span>` : ''}</div>${lifeLine(it)}</div>
        ${n > 1 ? `<button class="btn" data-act="${act}" data-id="${esc(id)}" data-n="${n}">${label} hết</button>` : ''}<button class="btn primary" data-act="${act}" data-id="${esc(id)}" data-n="1">${label}</button></div>`;
    };
    const inside = Object.keys(st.inv).map((id) => row(id, st.inv[id], 'unstore', 'Lấy'))
      .concat(st.gear.map((uid) => row(uid, 1, 'unstore', 'Lấy')));
    const bag = Object.keys(P.inv).filter((id) => P.inv[id] > 0).map((id) => row(id, P.inv[id], 'store', 'Cất'))
      .concat(bagGear().map((uid) => row(uid, 1, 'store', 'Cất')));
    const nx = st.next;
    return `<div class="card"><div class="row"><h3 class="grow">Trong tủ</h3><span class="tag num">Đồ thường ${Object.keys(st.inv).length}/${st.items_cap} loại · Đồ hiếm ${st.gear.length}/${st.cap}</span></div>
      ${inside.length ? `<div class="list">${inside.join('')}</div>` : '<p class="small muted">Tủ đang trống.</p>'}
      ${nx ? `<button class="btn block" data-act="storage_expand" ${P.gold < nx.gold ? 'disabled' : ''}>Thêm ${nx.gear} chỗ đồ hiếm · ${icon('two-coins')}${fmt(nx.gold)}</button>` : '<p class="small muted">Tủ đã mở rộng tối đa.</p>'}
    </div>
    <div class="card"><h3>Túi đồ</h3><p class="small muted">Đồ trong tủ không mất, không mặc / bán / giao dịch được cho tới khi lấy ra. Đồ đang mặc phải tháo ra trước.</p>
      ${bag.length ? `<div class="list">${bag.join('')}</div>` : '<p class="small muted">Túi trống.</p>'}</div>`;
  }

  // Máy Hỗn Nguyên (Lão Hỗn Nguyên): chọn công thức, chọn món đồ (nếu cần), xem tỉ lệ rồi ghép.
  let chaosPick = {}; // công thức → uid món đồ chọn
  const chaosRate = L.chaosRate;
  function chaosCard() {
    const rows = CHAOS.map((r) => {
      const fits = r.gear ? bagGear().filter((uid) => {
        const g = itemOf(uid);
        return r.gear.slots.includes(g.slot) && (!r.gear.tier || g.tier === r.gear.tier) && upLevel(uid) >= r.gear.min_up && !g.locked;
      }) : [];
      const pick = r.gear ? (fits.includes(chaosPick[r.id]) ? chaosPick[r.id] : fits[0]) : null;
      const need = Object.entries(r.items);
      const ok = (!r.gear || pick) && P.gold >= r.gold && need.every(([id, n]) => (P.inv[id] || 0) >= n);
      const rate = chaosRate(r, pick ? upLevel(pick) : 0);
      const out = ITEMS[r.out.replace('{cls}', P.cls)];
      return `<div class="item">${itemIcon(out || { icon: 'chaos-machine' })}<div class="grow">
          <div class="name">${esc(r.name)}${out && out.slot === 'wing' ? ` → ${esc(out.name)}` : ''}</div>
          <div class="small muted">${esc(r.desc)}</div>
          ${r.gear ? (fits.length ? `<select data-chaos-pick="${r.id}" aria-label="Món đồ bỏ vào máy">${fits.map((uid) => `<option value="${uid}" ${uid === pick ? 'selected' : ''}>${esc(itemOf(uid).name)} +${upLevel(uid)}</option>`).join('')}</select>`
            : `<div class="small" style="color:var(--bad)">Không có món phù hợp trong túi (cần +${r.gear.min_up} trở lên, chưa mặc, chưa khóa).</div>`) : ''}
          <div class="small">${need.map(([id, n]) => `<span style="${(P.inv[id] || 0) >= n ? '' : 'color:var(--bad)'}">${ITEMS[id].name} ${Math.min(P.inv[id] || 0, n)}/${n}</span>`).join(' · ')} · Tỉ lệ <b>${Math.round(rate * 100)}%</b></div>
        </div>
        <button class="btn ${ok ? 'primary' : ''}" data-act="chaos" data-id="${r.id}" data-gear="${pick || ''}" ${ok ? '' : 'disabled'}>${icon('two-coins')}${fmt(r.gold)}</button>
      </div>`;
    }).join('');
    return `<div class="card"><h3>${icon('chaos-machine')} Máy Hỗn Nguyên</h3>
      <p class="small muted">Thất bại thì <b style="color:var(--bad)">mất hết</b> món đồ, nguyên liệu và vàng. Đồ đã khóa không bỏ vào máy được. Đồ cấp nâng cao hơn thì dễ thành hơn (tối đa 60%).</p>
      <div class="list">${rows}</div></div>`;
  }

  function chestCard() {
    const full = bagGear().length >= RULES.gearBag;
    const odds = (o) => [[3, 'Sử Thi'], [2, 'Hiếm'], [1, 'Tốt']].filter(([r]) => o[r]).map(([r, n]) => `<span class="rar-${r}">${n} ${o[r]}%</span>`).join(' · ');
    return `<div class="card"><h3>Rương Báu</h3>
      <p class="small muted">Mở ra một món đồ chỉ số ngẫu nhiên hợp cấp của bạn.${full ? ' <span style="color:var(--bad)">Túi đồ hiếm đầy, bán bớt đã.</span>' : ''}</p>
      <div class="list">${P.view.chests.map((c) => `<div class="item">
        <img class="ic lg px" src="${asset('items/chest_' + c.id + '.png')}" alt="">
        <div class="grow"><div class="name">${c.name}</div><div class="small">${odds(c.odds)}</div></div>
        <button class="btn ${P.gold >= c.price && !full ? 'primary' : ''}" data-act="chest_buy" data-tier="${c.id}" ${P.gold >= c.price && !full ? '' : 'disabled'}>${icon('two-coins')}${fmt(c.price)}</button>
      </div>`).join('')}</div></div>`;
  }

  // Món đang ăn (Crafting.food_bonus): tên và số trận còn tác dụng
  function foodNow() {
    if (!P.food) return '';
    const it = ITEMS[P.food.id];
    return `<p class="small" style="color:var(--good)">🍽 Đang no bụng: ${esc(it.name)} (${esc(it.desc.replace(/ trong \d+ trận\.?/, ''))}), còn ${P.food.left} trận.</p>`;
  }

  // Cấp nghề: thanh tiến độ tới cấp sau
  function craftLevel(kind, label) {
    const xp = (P.crafting && P.crafting[kind]) || 0, L = RULES.craftLevels;
    const lv = L.filter((x) => xp >= x).length, next = L[lv];
    return `<div class="row"><span class="grow small">Nghề ${label} <b style="color:var(--gold)">cấp ${lv}</b></span><span class="small muted">${next != null ? `${xp}/${next}` : 'tối đa'}</span></div>
      ${bar('xp', next != null ? xp - L[lv - 1] : 1, next != null ? next - L[lv - 1] : 1, next != null ? `${xp}/${next} lần` : 'Cấp tối đa')}`;
  }

  function cookCard() {
    const lv = P.view.crafting.cook;
    return `<div class="card"><h3>Nấu ăn</h3>${craftLevel('cook', 'Nấu ăn')}
      <p class="small muted">Ăn món ngon ngoài trận (tab Túi đồ) thì mạnh hơn trong vài trận. Mỗi lúc chỉ no một món.</p>${foodNow()}
      <div class="list">${RECIPES.filter((r) => r.npc === 'cook').map((r) => {
        const out = ITEMS[r.out], needs = Object.entries(r.needs), need = r.level || 1;
        const ok = lv >= need && needs.every(([id, n]) => (P.inv[id] || 0) >= n);
        return `<div class="item">${itemIcon(out)}<div class="grow"><div class="name">${esc(out.name)}</div>
          <div class="small">${esc(out.desc)}</div>
          <div class="small muted">${lv < need ? `<span style="color:var(--bad)">Cần nghề cấp ${need}</span> · ` : ''}${needs.map(([id, n]) => `${ITEMS[id].name} ${Math.min(P.inv[id] || 0, n)}/${n}`).join(' · ')}</div></div>
          <button class="btn ${ok ? 'primary' : ''}" data-act="cook" data-id="${r.id}" ${ok ? '' : 'disabled'}>Nấu</button></div>`;
      }).join('')}</div></div>`;
  }

  function smithCard() {
    const lv = P.view.crafting.smith, gold = P.view.crafting.smithGold;
    const epic = RULES.smithEpicPerLevel * lv, full = bagGear().length >= RULES.gearBag;
    const slots = [['weapon', 'Vũ khí'], ['armor', 'Giáp'], ['shield', 'Khiên']];
    return `<div class="card"><h3>Rèn đồ</h3>${craftLevel('smith', 'Rèn đồ')}
      <p class="small muted">Rèn một món đồ chỉ số ngẫu nhiên hợp cấp bạn: Sử Thi ${epic}%, Hiếm ${RULES.smithRare}%. Nghề càng cao càng dễ ra Sử Thi.${full ? ' <span style="color:var(--bad)">Túi đồ hiếm đầy.</span>' : ''}</p>
      <div class="list">${slots.map(([slot, label]) => {
        const cost = Object.entries(RULES.smithCosts[slot]);
        const ok = !full && P.gold >= gold && cost.every(([id, n]) => (P.inv[id] || 0) >= n);
        return `<div class="item"><div class="grow"><div class="name">${label}</div>
          <div class="small muted">${cost.map(([id, n]) => `${ITEMS[id].name} ${Math.min(P.inv[id] || 0, n)}/${n}`).join(' · ')} · ${fmt(gold)} vàng</div></div>
          <button class="btn ${ok ? 'primary' : ''}" data-act="smith" data-slot="${slot}" ${ok ? '' : 'disabled'}>${icon('anvil')} Rèn</button></div>`;
      }).join('')}</div></div>`;
  }

  function eventCard() {
    const e = P.view.event;
    if (!e.active) return `<div class="card"><h3>Lễ hội</h3><p class="small muted">Chưa tới mùa lễ hội. Sắp tới: ${e.next.icon} ${esc(e.next.name)} (còn ${e.next.days} ngày).</p></div>`;
    const have = P.inv[e.token] || 0, tok = ITEMS[e.token];
    return `<div class="card"><div class="row"><h3 class="grow">${e.icon} ${esc(e.name)}</h3><span class="tag gold num">${itemIcon(tok)} ${fmt(have)}</span></div>
      <p class="small muted">${esc(e.desc)} Mang ${esc(tok.name)} tới đây đổi quà.</p>
      <div class="list">${e.shop.map((o) => {
        const ok = have >= o.cost;
        return `<div class="item"><div class="grow"><div class="name">${esc(o.name)}</div><div class="small muted">${esc(o.desc)}</div></div>
          <button class="btn ${ok ? 'primary' : ''}" data-act="event_exchange" data-id="${o.id}" ${ok ? '' : 'disabled'}>${o.cost} ${esc(tok.name)}</button></div>`;
      }).join('')}</div></div>`;
  }

  function craftCard() {
    return `<div class="card"><h3>Pha thuốc · nấu cá</h3><div class="list">${RECIPES.filter((r) => r.npc === 'herbalist').map((r) => {
      const out = ITEMS[r.out];
      const needs = Object.entries(r.needs);
      const ok = needs.every(([id, n]) => (P.inv[id] || 0) >= n);
      return `<div class="item">${itemIcon(out)}<div class="grow"><div class="name">${out.name}</div>
        <div class="small muted">${needs.map(([id, n]) => `${ITEMS[id].name} ${Math.min(P.inv[id] || 0, n)}/${n}`).join(' · ')}</div></div>
        <button class="btn ${ok ? 'primary' : ''}" data-act="craft" data-id="${r.id}" ${ok ? '' : 'disabled'}>Pha</button></div>`;
    }).join('')}</div></div>`;
  }

  // Tiến độ nhiệm vụ đang làm (server vẫn là nơi kiểm tra cuối cùng).
  function questProgress(q) {
    const have = q.type === 'kill' ? (P.quests.active[q.id] || 0)
      : q.type === 'collect' ? (P.inv[q.target] || 0)
      : P.bosses.includes(q.target) ? 1 : 0;
    return [Math.min(have, q.count), q.count];
  }

  function questRow(q, action) {
    const reward = [`${fmt(q.reward.gold)} vàng`, `${fmt(q.reward.xp)} kinh nghiệm`]
      .concat(Object.entries(q.reward.items).map(([id, n]) => `${ITEMS[id].name} ×${n}`)).join(' · ');
    let right = '', progress = '';
    if (action !== 'accept') {
      const [have, need] = questProgress(q);
      progress = `<div class="small ${have >= need ? '' : 'muted'}" style="${have >= need ? 'color:var(--good)' : ''}">${have >= need ? 'Đã xong, về báo Trưởng Làng' : `Tiến độ ${have}/${need}`}</div>`;
      if (action === 'turnin') right = `<button class="btn ${have >= need ? 'primary' : ''}" data-act="quest_turnin" data-id="${q.id}" ${have >= need ? '' : 'disabled'}>Trả</button>`;
    } else {
      right = `<button class="btn primary" data-act="quest_accept" data-id="${q.id}">Nhận</button>`;
    }
    return `<div class="item quest"><div class="grow">
      <div class="name">${q.name} <span class="small muted">· ${ZONES[q.zone].name}</span></div>
      <div class="small muted">${q.desc}</div>
      ${progress}
      <div class="small" style="color:var(--gold)">Thưởng: ${reward}</div>
    </div>${right}</div>`;
  }

  const activeQuests = () => QUESTS.filter((q) => q.id in P.quests.active);
  const availableQuests = () => QUESTS.filter((q) => !(q.id in P.quests.active) && !P.quests.done.includes(q.id)
    && P.view.unlocked[q.zone] && q.requires.every((r) => P.quests.done.includes(r)));

  // ---------- Việc hằng ngày ----------
  // Nhiệm vụ bang trong tuần (HacLong.GuildQuests)
  function viewGuildQuest(q) {
    if (!q) return '';
    const d = Math.floor(q.left / 86400), h = Math.floor((q.left % 86400) / 3600);
    const left = d > 0 ? `${d} ngày ${h} giờ` : `${h} giờ ${Math.floor((q.left % 3600) / 60)} phút`;
    return `<div class="card"><div class="row"><h3 class="grow">📜 Nhiệm vụ bang tuần này</h3>${q.done ? '<span class="tag good">Đã xong</span>' : `<span class="small muted">còn ${left}</span>`}</div>
      <p><b>${esc(q.name)}</b>: cả bang cùng làm ${fmt(q.goal)} ${esc(q.unit)}.</p>
      ${bar('xp', Math.min(q.progress, q.goal), q.goal, `${fmt(Math.min(q.progress, q.goal))} / ${fmt(q.goal)}`)}
      <p class="small muted">Thưởng khi xong: quỹ bang +${fmt(q.reward.fund)}; mỗi thành viên ${fmt(q.reward.gold)} vàng, ${fmt(q.reward.xp)} kinh nghiệm qua hộp thư. Việc mới mỗi thứ Hai.</p>
    </div>`;
  }

  function dailyLeft() {
    const s = P.view.dailyLeft, h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
    return h ? `${h} giờ ${m} phút` : `${m} phút`;
  }

  function dailyList(claim) {
    const tasks = (P.daily && P.daily.tasks) || [];
    return `<div class="list">${tasks.map((t, i) => {
      const done = t.progress >= t.count;
      const right = t.claimed ? '<span class="tag good">Đã nhận</span>'
        : claim ? `<button class="btn ${done ? 'primary' : ''}" data-act="daily_claim" data-i="${i}" ${done ? '' : 'disabled'}>Nhận</button>` : '';
      return `<div class="item quest"><div class="grow">
        <div class="name">${esc(t.name)} <span class="small muted">· ${t.zone == null ? 'Bất kỳ hồ nào' : ZONES[t.zone].name}</span></div>
        <div class="small ${done ? '' : 'muted'}" style="${done && !t.claimed ? 'color:var(--good)' : ''}">${t.claimed ? 'Xong' : done ? 'Đã xong, đến Bảng Tin nhận thưởng' : `Tiến độ ${t.progress}/${t.count}`}</div>
        <div class="small" style="color:var(--gold)">Thưởng: ${fmt(t.reward.gold)} vàng · ${fmt(t.reward.xp)} kinh nghiệm</div>
      </div>${right}</div>`;
    }).join('')}</div>`;
  }

  function viewNpc() {
    const n = npcData(), d = P.view.derived;
    const sections = [];
    if (n.role === 'quests') {
      const act = activeQuests(), avail = availableQuests();
      sections.push(`<div class="card"><h3>Nhiệm vụ đang làm</h3>${act.length ? `<div class="list">${act.map((q) => questRow(q, 'turnin')).join('')}</div>` : '<p class="small muted">Chưa nhận nhiệm vụ nào.</p>'}</div>`);
      if (P.level >= RULES.maxLevel || P.rebirths) {
        const pts = ((P.rebirths || 0) + 1) * RULES.rebirthPoints, max = P.rebirths >= RULES.maxRebirths;
        sections.push(`<div class="card"><div class="row">${icon('star-cycle', 'lg')}<div class="grow"><h3>Chuyển sinh</h3>
          <p class="small muted">Đạt cấp ${RULES.maxLevel} thì có thể trở về cấp 1 để luyện lại từ đầu, giữ nguyên vàng, đồ đạc, vùng đã mở, nhiệm vụ và thành tựu. Mỗi lần chuyển sinh cho thêm ${RULES.rebirthPoints} điểm tiềm năng vĩnh viễn.</p>
          ${P.rebirths ? `<p class="small">Đã chuyển sinh ${P.rebirths}/${RULES.maxRebirths} lần.</p>` : ''}</div></div>
          ${max ? '' : P.level < RULES.maxLevel ? `<p class="small muted">Cần cấp ${RULES.maxLevel} để chuyển sinh lần tiếp theo.</p>`
            : confirmRebirth ? `<p class="small" style="color:var(--bad)">Về cấp 1 với ${pts} điểm tiềm năng? Không thể hoàn tác.</p>
              <div class="btn-row"><button class="btn" data-act="rebirth-cancel">Thôi</button><button class="btn primary" data-act="rebirth">Chuyển sinh</button></div>`
            : `<button class="btn primary block" data-act="rebirth-ask">${icon('star-cycle')} Chuyển sinh</button>`}
        </div>`);
      }
      sections.push(`<div class="card"><h3>Việc cần người giúp</h3>${avail.length ? `<div class="list">${avail.map((q) => questRow(q, 'accept')).join('')}</div>` : '<p class="small muted">Hiện chưa có việc mới. Mở thêm vùng đất để nhận thêm nhiệm vụ.</p>'}</div>`);
    }
    if (n.role === 'shop' || n.role === 'herbalist') {
      if (n.role === 'herbalist') sections.push(craftCard());
      if (n.role === 'shop') sections.push(forgeCard(), smithCard(), chestCard());
      sections.push(`<div class="card"><h3>Mua</h3><div class="list">${n.stock.map(shopRow).join('')}</div></div>`);
      sections.push(sellCard());
    }
    if (n.role === 'inn') {
      const full = P.hp >= d.maxHp && (P.mp || 0) >= d.maxMp, cost = P.view.restCost;
      sections.push(`<div class="card"><button class="btn ${full ? '' : 'primary'} block" data-act="rest" ${full ? 'disabled' : ''}>${full ? 'Máu và MP đang đầy' : cost ? `Nghỉ một đêm · ${fmt(cost)} vàng` : 'Nghỉ một đêm · miễn phí'}</button></div>`);
    }
    if (n.role === 'tower') {
      const best = P.tower_best || 0;
      const starts = []; for (let f = 1; f <= best + 1; f += 10) starts.push(f);
      const pots = ['potion_s', 'potion_m', 'potion_l'].reduce((s, id) => s + (P.inv[id] || 0), 0);
      sections.push(`<div class="card">
        <div class="row"><h3 class="grow">Tháp Vô Tận</h3><span class="tag gold num">Kỷ lục: tầng ${best}</span></div>
        <p class="small muted">Mỗi tầng hạ hết quái thì cầu thang lên mở và bạn nhận thưởng. Tầng N có quái cấp N, cứ 5 tầng có trùm tầng. Trong tháp máu không tự hồi; gục ngã là hết lượt. Muốn về thì đi cầu thang xuống ở đầu tầng.</p>
        ${pots ? '' : '<p class="small" style="color:var(--bad)">Bạn không có bình máu nào.</p>'}
        <div class="btn-row">${starts.map((f) => `<button class="btn ${f === starts[starts.length - 1] ? 'primary' : ''}" data-act="tower_enter" data-floor="${f}" ${P.hp <= 0 ? 'disabled' : ''}>Vào tầng ${f}</button>`).join('')}</div>
        ${starts.length === 1 ? '<p class="small muted">Vượt tầng 10 thì lần sau vào thẳng được tầng 11.</p>' : ''}
      </div>`);
    }
    if (n.role === 'daily') {
      sections.push(`<div class="card"><div class="row"><h3 class="grow">Việc hôm nay</h3><span class="small muted">Việc mới sau ${dailyLeft()}</span></div>${dailyList(true)}</div>`);
    }
    if (n.role === 'cook') sections.push(cookCard());
    if (n.role === 'event') sections.push(eventCard());
    if (n.role === 'pets') {
      const owned = P.pets || [];
      sections.push(`<div class="card"><h3>Thú cưng</h3><p class="small muted">Dắt theo một con để nó đi sau bạn trên bản đồ và giúp một tay. Đổi con dắt theo ở tab Nhân vật.</p>
        <div class="list">${PETS.map((pt) => {
          const has = owned.includes(pt.id), poor = P.gold < pt.price;
          return `<div class="item"><img class="sprite" src="${asset('pets/' + pt.id + '.png')}" alt=""><div class="grow"><div class="name">${esc(pt.name)}</div><div class="small muted">${esc(pt.desc)}</div></div>
            ${has ? (P.pet === pt.id ? '<span class="tag good">Đang dắt</span>' : `<button class="btn" data-act="pet_choose" data-id="${pt.id}">Dắt theo</button>`)
              : `<button class="btn ${poor ? '' : 'primary'}" data-act="pet_buy" data-id="${pt.id}" ${poor ? 'disabled' : ''}>${icon('two-coins')}${fmt(pt.price)}</button>`}</div>`;
        }).join('')}</div></div>`);
      const wild = ZONES.flatMap((z) => z.monsters).filter((m) => !owned.includes('tame:' + m.id));
      const count = (id) => (P.bestiary && P.bestiary[id]) || 0;
      const ready = wild.filter((m) => count(m.id) >= RULES.tameKills);
      const near = wild.filter((m) => count(m.id) < RULES.tameKills && count(m.id) > 0)
        .sort((a, b) => count(b.id) - count(a.id)).slice(0, 3);
      sections.push(`<div class="card"><h3>Thuần phục</h3><p class="small muted">Hạ đủ ${RULES.tameKills} con một loài quái thường thì mang về thuần được. Thú thuần: tấn công +${Math.round(RULES.tameBonus * 100)}%.</p>
        <div class="list">${ready.map((m) => {
          const price = tamePrice(m), poor = P.gold < price;
          return `<div class="item"><img class="sprite" src="${asset('monsters/' + m.id + '.png')}" alt=""><div class="grow"><div class="name">${esc(m.name)}</div><div class="small muted">Đã hạ ${fmt(count(m.id))} con</div></div>
            <button class="btn ${poor ? '' : 'primary'}" data-act="pet_tame" data-id="${m.id}" ${poor ? 'disabled' : ''}>${icon('two-coins')}${fmt(price)}</button></div>`;
        }).join('')}${near.map((m) => `<div class="item"><img class="sprite" src="${asset('monsters/' + m.id + '.png')}" alt="" style="opacity:.5"><div class="grow"><div class="name">${esc(m.name)}</div><div class="small muted">Tiến độ ${fmt(count(m.id))}/${RULES.tameKills}</div></div></div>`).join('')}
        ${ready.length || near.length ? '' : '<p class="small muted">Chưa có loài nào. Hạ thêm quái đi đã!</p>'}</div></div>`);
    }
    if (n.role === 'carpenter') {
      const stock = P.furniture || {};
      sections.push(`<div class="card"><h3>Đồ trang trí</h3><p class="small muted">Mua rồi về Nhà bấm Trang trí để đặt. Mỗi 10 điểm tiện nghi của đồ đã đặt: +1% kinh nghiệm mỗi trận (tối đa +5%). Nhà bạn đang có ${P.view.comfort} điểm.</p>
        <div class="list">${FURNITURE.filter((fu) => !fu.event).map((fu) => {
          const poor = P.gold < fu.price;
          return `<div class="item"><img class="sprite" src="${asset('decor/' + fu.id + '.png')}" alt=""><div class="grow"><div class="name">${esc(fu.name)}</div><div class="small muted">Tiện nghi +${fu.comfort}${stock[fu.id] ? ` · trong kho ${stock[fu.id]}` : ''}</div></div>
            <button class="btn ${poor ? '' : 'primary'}" data-act="decor_buy" data-id="${fu.id}" ${poor ? 'disabled' : ''}>${icon('two-coins')}${fmt(fu.price)}</button></div>`;
        }).join('')}</div></div>`);
    }
    if (n.role === 'market') sections.push(viewMarket());
    if (n.role === 'chaos') sections.push(chaosCard());
    if (n.role === 'tienlen') {
      sections.push(`<div class="card">${n.lines.map((l) => `<p>“${esc(l)}”</p>`).join('')}
        <button class="btn primary block" data-act="tl-open">${icon('card-fan')} Vào sòng Tiến Lên</button></div>`);
    }
    if (n.role === 'chest') {
      sections.push(`<div class="card"><p>“${esc(n.lines[0])}”</p>
        <button class="btn ${P.view.chestReady ? 'primary' : ''} block" data-act="chest_open" ${P.view.chestReady ? '' : 'disabled'}>${P.view.chestReady ? 'Mở rương' : 'Hôm nay đã mở, mai quay lại'}</button></div>`);
    }
    if (n.role === 'wardrobe') sections.push(wardrobeCard());
    if (n.role === 'talk') {
      sections.push(`<div class="card">${n.lines.map((l) => `<p>“${esc(l)}”</p>`).join('')}</div>`);
    }
    // V5: nút quay về bản đồ ở trên cùng (như "‹ Menu"); vẫn giữ nút Rời đi ở cuối
    return `<div class="row menu-head"><button class="btn" data-act="npc-close">‹ Bản đồ</button><span class="grow"></span></div>
      <div class="card npc-head">
        <div class="row"><img class="sprite" src="${asset('npcs/' + n.sprite + '.png')}" alt="${esc(n.name)}"><div class="grow"><h2 class="display">${esc(n.name)}</h2>
        ${n.role !== 'talk' ? `<p class="small muted">“${esc(npc.line)}”</p>` : ''}</div></div>
      </div>
      ${sections.join('')}
      <button class="btn block" data-act="npc-close">${icon('walk')} Rời đi</button>`;
  }

  // ---------- Nhiệm vụ ----------
  function viewQuests() {
    const act = activeQuests();
    return `<h2 class="display">Nhiệm vụ</h2>
      <div class="card"><div class="row"><h3 class="grow">Việc hằng ngày</h3><span class="small muted">Việc mới sau ${dailyLeft()}</span></div>
        ${dailyList(false)}
        <p class="small muted">Tự tính khi bạn làm; xong thì đến Bảng Tin trong Làng nhận thưởng.</p>
      </div>
      <h3>Nhiệm vụ của Trưởng Làng</h3>
      <div class="card">${act.length ? `<div class="list">${act.map((q) => questRow(q, 'log')).join('')}</div>` : '<p class="small muted">Chưa nhận nhiệm vụ nào. Gặp Trưởng Làng (ông già ở giữa Làng, phía trên) để nhận việc.</p>'}</div>
      <p class="small muted">Đã hoàn thành ${P.quests.done.length}/${QUESTS.length} nhiệm vụ.${availableQuests().length ? ` Trưởng Làng đang có ${availableQuests().length} việc mới.` : ''}</p>`;
  }

  // ---------- Trận đấu ----------
  const mySkills = () => CLASSES[P.cls].skills.filter((k) => k.level <= P.level);

  // Hiệu ứng trạng thái đang có (độc, choáng, cuồng nộ...).
  const EFFECTS = {
    poison: ['☠', 'Trúng độc', 'bad'], burn: ['🔥', 'Bỏng', 'bad'], bleed: ['🩸', 'Chảy máu', 'bad'],
    stun: ['💫', 'Choáng', 'bad'], weaken: ['⬇', 'Suy yếu', 'bad'],
    rage: ['⬆', 'Cuồng nộ', 'good'], guard: ['🛡', 'Thủ thế', 'good'], evade: ['💨', 'Ảnh bộ', 'good'],
  };
  function effectTags(list) {
    if (!list || !list.length) return '';
    return `<div class="fx-tags">${list.map((e) => {
      const [ic, name, kind] = EFFECTS[e.id] || ['•', e.id, ''];
      const dot = ['poison', 'burn', 'bleed'].includes(e.id) ? ` -${e.power}` : '';
      return `<span class="fx-tag ${kind}" title="${name}">${ic} ${name}${dot}${e.id === 'stun' ? '' : ` · ${e.turns}`}</span>`;
    }).join('')}</div>`;
  }
  function viewBattle() {
    const b = P.battle, m = b.monster, d = P.view.derived;
    // bản đồ phụ (Phase 15a) không thuộc vùng: nền theo `theme`, tên theo `place`
    const z = b.zone != null && ZONES[b.zone] ? ZONES[b.zone] : { id: b.theme || 'forest', name: b.place || '' };
    const skills = mySkills();
    const cd = (id) => { const c = (b.cds || []).find((x) => x.id === id); return c ? c.turns : 0; };
    const fxs = (!b.over && b.effects) || { player: [], monster: [] };
    const dotted = fxs.player.some((e) => ['poison', 'burn', 'bleed'].includes(e.id));
    const pots = ['potion_s', 'potion_m', 'potion_l'].reduce((s, id) => s + (P.inv[id] || 0), 0);
    const manas = ['mana_s', 'mana_m', 'mana_l'].reduce((s, id) => s + (P.inv[id] || 0), 0);
    const floatHtml = fx && fx.mDmg != null
      ? `<span class="float ${fx.crit ? 'crit' : ''} ${fx.mDmg === 0 ? 'miss' : ''}">${fx.mDmg === 0 ? 'Trượt' : '-' + fmt(fx.mDmg)}</span>` : '';
    // đồ sát: luân phiên lượt với người thật, chưa tới lượt thì khóa nút
    const slayEnc = b.live && b.encounter ? b.encounter : null;
    // hạn lượt theo đồng hồ máy mình: server gửi số mili giây còn lại lúc gửi (`view.slayLeft`)
    if (slayEnc && P.view.slayLeft !== slayClock.left) slayClock = { left: P.view.slayLeft, until: Date.now() + (P.view.slayLeft || 0) };
    const wait = slayEnc && !slayEnc.mine ? 'disabled' : '';
    let bottom;
    if (!b.over) {
      bottom = `
        ${slayEnc ? `<p class="slay-turn ${slayEnc.mine ? 'mine' : ''}">${slayEnc.mine ? '🗡 Lượt của bạn' : '⏳ Lượt của đối thủ'} · <span class="num" data-until="${slayClock.until}">${slayLeft(slayClock.until)}</span>s</p>` : ''}
        <div class="actions">
          <button class="btn primary" data-act="attack" ${wait}>${icon('broadsword')}<span class="lbl">Tấn công</span></button>
          ${skills.map((k) => { const kmp = skillMp(k), noMp = (P.mp || 0) < kmp; return `<button class="btn" data-act="skill" data-skill="${k.id}" ${cd(k.id) || noMp || wait ? 'disabled' : ''} title="${k.name} · ${kmp} MP">${icon(k.icon)}<span class="lbl">${k.name}</span><span class="sub num">${cd(k.id) ? `chờ ${cd(k.id)}` : `${kmp} MP`}</span></button>`; }).join('')}
        </div>
        <div class="actions util">
          <button class="btn" data-act="potion" ${pots && (P.hp < d.maxHp || dotted) && !wait ? '' : 'disabled'} title="Uống máu">${icon('health-potion')}<span class="lbl">Máu</span><span class="sub num">${pots}</span></button>
          <button class="btn" data-act="mana" ${manas && (P.mp || 0) < d.maxMp && !wait ? '' : 'disabled'} title="Uống mana">${icon('magic-potion')}<span class="lbl">Mana</span><span class="sub num">${manas}</span></button>
          <button class="btn" data-act="flee" ${wait} title="${slayEnc ? 'Bỏ chạy: tính như gục ngã' : 'Bỏ chạy'}">${icon('walk')}<span class="lbl">Chạy</span>${slayEnc ? '<span class="sub">= chết</span>' : ''}</button>
        </div>`;
    } else {
      const r = b.result, rw = b.reward;
      const title = r === 'win' ? (m.final ? 'Hắc Long đã chết!' : 'Chiến thắng!') : r === 'lose' ? 'Gục ngã' : 'Đã thoát';
      bottom = `
        <div class="card result ${r}">
          <h2>${title}</h2>
          ${rw ? `<p class="num">+${fmt(rw.xp)} kinh nghiệm · +${fmt(rw.gold)} vàng${rw.items.length ? ' · ' + rw.items.map((id) => ITEMS[id].name).join(', ') : ''}</p>` : ''}
          ${rw && rw.gear ? `<p class="gear-drop">🎁 ${rw.gear.map(esc).join(', ')}</p>` : ''}
          ${rw && rw.levels ? `<p style="color:var(--gold);font-weight:600">Lên cấp ${P.level}! Vào tab Nhân vật để cộng điểm.</p>` : ''}
          <div class="btn-row">
            <button class="btn primary" data-act="leave">${r === 'lose' ? `${icon('village')} Về nhà` : `${icon('walk')} Tiếp tục`}</button>
          </div>
          ${r !== 'lose' && P.hp < d.maxHp * 0.35 ? '<p class="small" style="color:var(--bad)">Máu đang thấp. Nên uống máu hoặc về Nhà uống nước giếng.</p>' : ''}
        </div>`;
    }
    return `
      <div class="stage ${m.boss ? 'boss' : ''} ${m.world ? 'world' : ''} ${m.golden ? 'golden' : ''}" style="background-image:url('${asset('floors/' + z.id + '.png')}')">
        <span class="eyebrow">${slayEnc ? '🗡 Đồ sát' : m.pvp ? 'Đấu trường' : b.encounter && b.encounter.shared && sharedN > 1 ? `${z.name} · Đánh cùng tổ đội (${sharedN} người)` : m.world ? 'Trùm thế giới · Tế Đàn' : m.tower ? `Tháp Vô Tận${P.tower ? ' · Tầng ' + P.tower.floor : ''}${m.elite ? ' · Trùm tầng' : ''}` : z.name + (m.boss ? ' · Trùm' : '')}</span>
        ${m.pvp ? `<img class="sprite ${fx && fx.mDmg ? 'hit' : ''}" src="${window.Doll.url(m.look)}" alt="${esc(m.name)}">` : sprite(m.id, fx && fx.mDmg ? 'hit' : '', m.name)}
        ${floatHtml}
        <h2>${m.name}</h2>
        <span class="small muted">Cấp ${m.level} · Tấn công ${m.atk} · Phòng thủ ${m.def}${m.special && !b.live ? ` · ${m.special.name} mỗi ${m.special.every} lượt` : ''}</span>
        ${bar(m.golden ? 'gold' : m.boss || m.world || m.elite ? 'boss' : 'hp', m.hp, m.maxHp)}
        ${effectTags(fxs.monster)}
      </div>
      <div class="me ${fx && fx.pDmg ? 'hurt' : ''}">
        ${heroSprite()}
        <div class="grow" style="flex:1;min-width:0">${bar('hp', P.hp, d.maxHp, `${esc(P.name)} · ${fmt(P.hp)} / ${fmt(d.maxHp)}`)}${bar('mp', P.mp || 0, d.maxMp, `💧 ${fmt(P.mp || 0)} / ${fmt(d.maxMp)}`)}${effectTags(fxs.player)}</div>
      </div>
      <div class="log" aria-live="polite">${b.log.map((l) => `<div class="${l.kind}">${esc(l.text)}</div>`).join('')}</div>
      ${bottom}`;
  }

  let slayClock = { left: null, until: 0 };
  function slayLeft(until) { return Math.max(0, Math.ceil(((until || 0) - Date.now()) / 1000)); }
  // đếm ngược lượt đồ sát (không vẽ lại cả màn hình)
  setInterval(() => { document.querySelectorAll('.slay-turn [data-until]').forEach((el) => { el.textContent = slayLeft(+el.dataset.until); }); }, 500);

  // ---------- Xử lý thao tác ----------
  // Ghi lại trạng thái trước một lượt đánh để tính hiệu ứng (số sát thương bay lên, rung).
  function snapBattle() {
    return { mHp: P.battle.monster.hp, pHp: P.hp, logLen: P.battle.log.length };
  }

  function battleFx(before, action) {
    if (!P || !P.battle) return;
    // Nhật ký giới hạn 60 dòng; khi đã đầy thì xem vài dòng cuối.
    const newLog = before.logLen < 60 ? P.battle.log.slice(before.logLen) : P.battle.log.slice(-4);
    const struck = action === 'attack' || action === 'skill';
    fx = {
      mDmg: struck ? before.mHp - P.battle.monster.hp : null,
      pDmg: before.pHp - P.hp > 0 ? before.pHp - P.hp : 0,
      crit: newLog.some((l) => l.kind === 'crit'),
    };
  }

  // Tên thao tác của nút → lệnh gửi server (xem lib/hac_long/game/commands.ex).
  function command(act, t) {
    const d = t.dataset;
    switch (act) {
      case 'alloc': return { act, stat: d.stat, n: 1 };
      case 'alloc5': return { act: 'alloc', stat: d.stat, n: 5 };
      case 'buy': return { act, id: d.id, n: 1 };
      case 'buy5': return { act: 'buy', id: d.id, n: 5 };
      case 'equip': case 'use': case 'sell': return { act, id: d.id };
      case 'unequip': return { act, slot: d.slot };
      case 'upgrade': return { act, slot: d.slot, id: d.id, confirm: d.risk === 'destroy' };
      case 'life': return { act, slot: d.slot, id: d.id };
      case 'discard': case 'store': case 'unstore': return { act, id: d.id, n: +d.n || 1 };
      case 'lock': return { act, id: d.id, on: d.on === '1' };
      case 'chaos': return { act, id: d.id, gear: d.gear || null };
      case 'reset-yes': return { act: 'reset' };
      case 'teleport': return { act, to: d.to };
      case 'craft': case 'quest_accept': case 'quest_turnin': case 'cook': case 'event_exchange': return { act, id: d.id };
      case 'smith': return { act, slot: d.slot };
      case 'daily_claim': return { act, i: +d.i };
      case 'tower_enter': return { act, floor: +d.floor };
      case 'skill': return { act, skill: d.skill };
      case 'mail_claim': return { act, id: +d.id };
      case 'chest_buy': return { act, tier: d.tier };
      case 'pvp_challenge': return { act, uid: +d.uid };
      case 'market_buy': case 'market_cancel': return { act, listing: +d.listing };
      case 'pet_buy': case 'pet_tame': case 'decor_buy': return { act, id: d.id };
      case 'pet_choose': return { act, id: d.id || null };
      case 'title_set': return { act, id: d.id || null };
      default: return { act };
    }
  }

  // Âm thanh cho kết quả một lệnh.
  const CMD_SOUND = { market_buy: 'coin', market_sell: 'coin', market_cancel: 'gather', pet_buy: 'rare', pet_tame: 'rare', decor_buy: 'coin', decor_place: 'forge', decor_take: 'gather', chest_buy: 'rare', chest_open: 'rare', rebirth: 'levelup', buy: 'coin', sell: 'coin', mail_claim: 'coin', mail_claim_all: 'coin', craft: 'brew', cook: 'brew', smith: 'forge', event_exchange: 'rare', upgrade: 'forge', life: 'forge', chaos: 'rare', store: 'gather', unstore: 'gather', storage_expand: 'coin', discard: 'gather', lock: 'gather', quest_turnin: 'quest', daily_claim: 'quest', quest_accept: 'notice', rest: 'potion', use: 'potion', tower_enter: 'portal', potion: 'potion' };

  function commandSound(cmd, r, old) {
    if (!r.ok) { Sound.play('error'); return; }
    if (fx) {
      if (cmd.act === 'skill') Sound.play('skill');
      if (cmd.act === 'potion' || cmd.act === 'mana') Sound.play('potion');
      if (fx.mDmg === 0) Sound.play('miss'); else if (fx.mDmg) Sound.play(fx.crit ? 'crit' : 'hit');
      if (fx.pDmg) setTimeout(() => Sound.play('hurt'), 180);
    } else if (CMD_SOUND[cmd.act]) Sound.play(CMD_SOUND[cmd.act]);
    if (cmd.act === 'flee' && P.battle && P.battle.over && P.battle.result === 'fled') Sound.play('flee');
    const ended = old && old.battle && !old.battle.over && P && P.battle && P.battle.over;
    if (ended && P.battle.result === 'win') setTimeout(() => Sound.play('win'), 250);
    if (ended && P.battle.result === 'lose') setTimeout(() => Sound.play('lose'), 250);
    if (old && P && P.level > old.level) setTimeout(() => Sound.play('levelup'), ended ? 700 : 100);
  }

  async function sendCommand(cmd) {
    if (busy) return;
    busy = true;
    const battle = ['attack', 'skill', 'potion', 'mana', 'flee'].includes(cmd.act) && P && P.battle;
    const before = battle ? snapBattle() : null;
    const scroll = $('#view').scrollTop;
    const old = P;
    try {
      const r = await Net.send(cmd);
      P = r.player;
      result(r);
      if (r.ok && before) battleFx(before, cmd.act);
      commandSound(cmd, r, old);
      resultFx(cmd, r, old);
      if (r.ok) {
        if (cmd.act === 'leave' || cmd.act === 'create') tab = 'map';
        if (cmd.act === 'reset') tab = 'map';
        if (cmd.act === 'tower_enter') { tab = 'map'; npc = null; }
        if (cmd.act.startsWith('market_')) market.data = null;
        if (cmd.act === 'rebirth' || cmd.act === 'guild_create' || cmd.act === 'guild_donate') board.at = 0;
        if ((cmd.act === 'upgrade' || cmd.act === 'life') && cmd.id && r.uid) forgePick = r.uid;
        if (cmd.act === 'mail_claim_all' && mail.list) mail.list.forEach((m) => { m.claimed = true; });
        if (cmd.act === 'mail_claim' && mail.list) { const m = mail.list.find((x) => x.id === cmd.id); if (m) m.claimed = true; }
        confirmReset = false;
        confirmRebirth = false;
        dialog = null;
      }
    } catch (e) {
      toast(e.msg, true);
    }
    busy = false;
    render();
    if (cmd.act === 'create' || cmd.act === 'reset') $('#view').scrollTop = 0;
    else if (!P || !P.battle) $('#view').scrollTop = scroll;
  }

  // ---------- Đi trên bản đồ ----------
  // Một bước: gửi lên server, server kiểm tra rồi trả vị trí mới (hoặc bắt đầu trận).
  async function step(dir, confirm) {
    if (busy || !P || P.battle) return false;
    if (fishing) { stopFishing(); toast('Bạn đã thu cần.'); }
    busy = true;
    const mapBefore = P.pos.map, hadDialog = !!dialog, floorBefore = P.tower ? P.tower.floor : null;
    dialog = null;
    let ok = false;
    try {
      // V9: gặp trùm vào trận luôn như quái thường (không hỏi Đấu / Thôi)
      const r = await Net.send({ act: 'move', dir, confirm: true });
      P = r.player;
      if (r.msg) result(r);
      if (r.gather) Sound.play('gather');
      else if (P.battle) Sound.play('encounter');
      else if (P.pos.map !== mapBefore) Sound.play('portal');
      else if (r.msg && r.ok) Sound.play('notice');
      if (r.confirm === 'boss') dialog = { type: 'boss', dir, boss: r.boss };
      if (r.waystone) dialog = { type: 'waystone' };
      if (r.npc) {
        const n = WORLD.maps[P.pos.map].npcs.find((x) => x.id === r.npc);
        npc = { map: P.pos.map, id: r.npc, line: n.lines[Math.floor(Math.random() * n.lines.length)] || '' };
      }
      // lên tầng tháp cũng như sang bản đồ mới: dừng đường đi đang chạy (B2)
      ok = r.ok && !P.battle && P.pos.map === mapBefore && (P.tower ? P.tower.floor : null) === floorBefore && !dialog && !npc;
    } catch (e) {
      toast(e.msg, true);
    }
    busy = false;
    const newFloor = P && (P.tower ? P.tower.floor : null) !== floorBefore;
    if (!P || P.battle || P.pos.map !== mapBefore || newFloor || dialog || hadDialog || npc) { walk = null; render(); if (npc) $('#view').scrollTop = 0; } else refresh();
    return ok;
  }

  // Đi dần tới ô đích (hoặc đuổi theo con quái đã chạm vào), tính lại đường sau mỗi bước.
  async function walkTo(x, y) {
    const target = Map_.monsterAt(x, y);
    const me = { x, y, monster: target ? target.id : null, id: Symbol('walk') };
    walk = me;
    // B2: trong tháp, lên tầng vẫn là bản đồ `tower`; tầng đổi thì dừng (không đi tiếp tới cùng toạ độ ở tầng mới)
    const floor0 = P && P.tower ? P.tower.floor : null;
    for (let i = 0; i < 200 && walk === me && P && !P.battle && (P.tower ? P.tower.floor : null) === floor0; i++) {
      if (me.monster != null) {
        const q = Map_.monsterById(me.monster);
        if (!q) break;
        me.x = q.x; me.y = q.y;
      }
      const dir = Map_.nextStep(P, me.x, me.y);
      if (!dir) break;
      const started = Date.now();
      if (!(await step(dir))) break;
      const wait = 130 - (Date.now() - started);
      if (wait > 0) await new Promise((res) => setTimeout(res, wait));
    }
    if (walk === me) walk = null;
  }

  const TAB_KEY = { hero: 'C', bag: 'I', map: 'M' };
  // Chuyển tab (nút thanh tab và phím tắt dùng chung)
  function goTab(id) {
    // tên tab cũ (Nhiệm vụ, Khác, Quản trị) giờ là mục trong Menu
    const sec = { quests: 'quests', misc: null, admin: 'admin' };
    if (id in sec) { menuSec = sec[id]; id = 'menu'; } else if (id === 'menu' && tab !== 'menu') menuSec = null;
    tab = id; confirmReset = false; profileUi = { open: false, info: null }; mail.open = false; notes.open = false; guildUi.open = false; visit = null; friendsUi.open = false;
    stopFishing();
    if (decor.on) { decor = { on: false, pick: null }; Map_.setDecorating(false); }
    render(); $('#view').scrollTop = 0;
  }

  // Phím tắt (như MU Web): C Nhân vật, I Túi đồ, M Bản đồ (bấm lại phím của tab đang mở thì về Bản đồ),
  // Q uống bình máu (trong trận: nút Uống máu), Enter gõ chat, Esc đóng bảng đang mở / về Bản đồ.
  // Không chạy khi đang gõ chữ hoặc giữ Ctrl / Alt / Cmd.
  // M: bảng chọn bản đồ (Phase 15a); bấm lại M thì về Bản đồ
  const HOTKEY_TAB = { c: 'hero', i: 'bag', m: 'travel' };
  function hotkeyPotion() {
    if (P.battle) {
      const b = document.querySelector('[data-act="potion"]');
      if (b && !b.disabled) sendCommand({ act: 'potion' }); else toast('Không uống máu được lúc này.', true);
      return;
    }
    if (P.hp >= P.view.derived.maxHp) { toast('Máu đang đầy.'); return; }
    // bình nhỏ nhất đang có (như MU: lấy stack đầu tiên của loại bình)
    const id = Object.keys(ITEMS).find((k) => ITEMS[k].heal_pct && P.inv[k] > 0);
    if (id) sendCommand({ act: 'use', id }); else toast('Hết bình máu. Mua ở Bà Lang trong Làng.', true);
  }
  function hotkeyEscape() {
    if (chatOpen) { toggleChat(false); return true; }
    if (tipAt) { hideTip(); return true; }
    if (npc) { npc = null; market.data = null; render(); return true; }
    if (dialog) { dialog = null; render(); return true; }
    if (mail.open || notes.open || guildUi.open || friendsUi.open || visit) { mail.open = false; notes.open = false; guildUi.open = false; friendsUi.open = false; if (visit) { visit = null; Map_.stopVisit(); } render(); return true; }
    if (!P.battle && tab !== 'map') { goTab('map'); return true; }
    return false;
  }

  function onKey(e) {
    if (window.TL && window.TL.isOpen()) return;
    if (!P || e.ctrlKey || e.metaKey || e.altKey || e.target.closest('input, textarea, select')) return;
    const k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
    if (k === 'Escape') { if (hotkeyEscape()) e.preventDefault(); return; }
    if (k === 'q') { e.preventDefault(); hotkeyPotion(); return; }
    if (P.battle) return;
    if (e.key === 'Tab' && !P.battle) { e.preventDefault(); goTab(tab === 'menu' ? 'map' : 'menu'); return; }
    if (HOTKEY_TAB[k]) { e.preventDefault(); goTab(tab === HOTKEY_TAB[k] ? 'map' : HOTKEY_TAB[k]); return; }
    if (k === 'Enter' && tab === 'map' && !npc) { e.preventDefault(); toggleChat(true); return; }
    if (tab !== 'map') return;
    if (npc) return;
    const dir = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right', w: 'up', s: 'down', a: 'left', d: 'right' }[e.key];
    if (!dir) return;
    e.preventDefault();
    walk = null;
    step(dir);
  }

  function onMapTap(e) {
    if (e.target.id !== 'map-canvas' || !P || P.battle) return;
    const [x, y] = Map_.tileFromEvent(e);
    if (decor.on && P.pos.map === 'home') { decorTap(x, y); return; }
    const other = Map_.playerAt(x, y);
    if (other) { openPlayer(other); return; }
    walkTo(x, y);
  }

  function enter(r) {
    P = r ? r.player : null;
    if (r) { Map_.setUser(r.user_id); Net.userId = r.user_id; Net.isAdmin = r.admin; Net.role = r.role || 'player'; blocked = r.blocked || []; mail = { unread: r.mail || 0, list: null, open: false, filter: 'all' }; party = r.party || null; trade = r.trade || null; visit = null; friendsUi = { open: false, data: null, chat: null, dm: r.dm || 0 }; notes.open = false; loadNotes(); Net.friends('list').then((d) => { friendsUi.data = d; friendsUi.dm = d.unread; refreshHud(); }).catch(() => {}); }
    tab = 'map';
    loading = false;
    render();
  }

  function logout() {
    Net.logout();
    P = null;
    npc = null; dialog = null; pwForm = false;
    confirmReset = false;
    render();
  }

  function onClick(e) {
    const t = e.target.closest('button');
    if (!t) return;
    if (t.dataset.cls) { pickCls = t.dataset.cls; document.querySelectorAll('.class-opt').forEach((b) => b.setAttribute('aria-pressed', b.dataset.cls === pickCls)); return; }
    // V4: bấm lại icon dock đang mở thì đóng, về Bản đồ
    if (t.dataset.tab) { const open = tab === t.dataset.tab && t.dataset.tab !== 'map' && !profileUi.open && !mail.open && !notes.open && !guildUi.open && !friendsUi.open && !visit; goTab(open ? 'map' : t.dataset.tab); return; }
    // Tiến Lên (Phase 17) mở lớp phủ riêng (tienlen.js), không phải một mục Menu
    if (t.dataset.menu === 'tienlen') { window.TL.open(); return; }
    if (t.dataset.menu) { menuSec = t.dataset.menu; render(); $('#view').scrollTop = 0; if (menuSec === 'admin' && adm.reports == null && !adm.loading) loadReports(); return; }
    if (t.dataset.auth) { authMode = t.dataset.auth; render(); return; }
    if (t.dataset.boardCls !== undefined) { board.cls = t.dataset.boardCls || null; const el = $('#board'); if (el) el.outerHTML = viewBoard(); return; }
    if (t.dataset.board) { board.kind = t.dataset.board; const el = $('#board'); if (el) el.outerHTML = viewBoard(); loadBoard(); return; }
    if (t.dataset.move) { walk = null; step(t.dataset.move); return; }
    const act = t.dataset.act;
    if (act === 'map-zoom') { setPref('hl-zoom', pref('hl-zoom', '0') === '1' ? '0' : '1'); t.classList.toggle('on'); t.setAttribute('aria-pressed', t.classList.contains('on')); Map_.draw(); return; }
    if (act === 'theme') { setPref('hl-theme', t.dataset.theme); render(); return; }
    if (act === 'lang') { if (window.I18N && t.dataset.lang !== window.I18N.lang) window.I18N.set(t.dataset.lang); return; }
    if (act === 'logout') return logout();
    if (act === 'pw-toggle') { pwForm = !pwForm; render(); return; }
    if (t.dataset.adm) { onAdmin(t); return; }
    if (t.dataset.chat) { chatMenu = chatMenu === +t.dataset.chat ? null : +t.dataset.chat; const log = $('#chat-log'); if (log) log.innerHTML = chats.map(ovLine).join(''); return; }
    if (act === 'chat-report') { Net.report(+t.dataset.id).then(() => toast('Đã gửi báo cáo. Cảm ơn bạn.')).catch((e) => toast(e.msg, true)); chatMenu = null; return; }
    if (act === 'chat-block' || act === 'unblock') {
      const uid = +t.dataset.uid;
      (act === 'unblock' ? Net.unblock(uid) : Net.block(uid)).then((r) => {
        blocked = r.blocked;
        if (act === 'chat-block') { chats = chats.filter((m) => m.uid !== uid); toast('Đã chặn. Bạn sẽ không thấy chat của người này.'); }
        chatMenu = null;
        render();
      }).catch((e) => toast(e.msg, true));
      return;
    }
    if (act === 'logout-all') {
      Net.logoutAll().then(() => { P = null; render(); toast('Đã đăng xuất mọi thiết bị.'); }).catch((err) => toast(err.msg, true));
      return;
    }
    if (!act || !P) return;
    if (act === 'reset-ask' || act === 'reset-cancel') { confirmReset = act === 'reset-ask'; render(); return; }
    if (act === 'rebirth-ask' || act === 'rebirth-cancel') { confirmRebirth = act === 'rebirth-ask'; render(); return; }
    if (act === 'dialog-close') { dialog = null; render(); return; }
    if (act === 'noop') return;
    if (act === 'alloc-add') { allocAdd(t.dataset.stat); return; }
    if (act === 'bag-tip' || act === 'slot-tip') {
      const same = tipAt && (act === 'bag-tip' ? tipAt.id === t.dataset.id : tipAt.slot === t.dataset.slot);
      if (same) hideTip(); else showTip(act === 'bag-tip' ? { id: t.dataset.id, x: e.clientX, y: e.clientY } : { slot: t.dataset.slot, x: e.clientX, y: e.clientY });
      return;
    }
    if (act === 'trade-op') { const d = t.dataset; tradeOp(d.op, d.uid ? { uid: +d.uid } : {}); return; }
    if (act === 'pk-op') { pkOp(t.dataset.op); return; }
    if (act === 'slay') { slay(+t.dataset.uid); return; }
    if (act === 'trade-rm') {
      const d = t.dataset;
      tradeOffer((o) => { if (d.kind === 'item') delete o.items[d.id]; else if (d.kind === 'gear') o.gear = o.gear.filter((u) => u !== d.id); else o.gold = 0; });
      return;
    }
    if (act === 'home-visit') { walk = null; friendsUi.open = false; openVisit(+t.dataset.uid); $('#view').scrollTop = 0; return; }
    if (act === 'visit-close') { visit = null; Map_.stopVisit(); render(); return; }
    if (act === 'home-like') {
      const v = visit && visit.info;
      Net.homeLike(+t.dataset.uid).then((r) => {
        if (v) { v.likes = r.likes; v.liked = true; }
        Sound.play('quest'); toast('Đã khen nhà!'); render();
      }).catch((e) => toast(e.msg, true));
      return;
    }
    if (act === 'market-tab') { market.tab = t.dataset.tab2; render(); return; }
    if (act === 'market-reload') { market.data = null; render(); return; }
    if (act === 'party-invite') { partyOp('invite', { uid: +t.dataset.uid }); return; }
    if (act === 'party-accept') { partyOp('accept'); return; }
    if (act === 'party-decline') { partyOp('decline'); return; }
    if (act === 'party-leave') { partyOp('leave'); return; }
    if (act === 'party-kick') { partyOp('kick', { uid: +t.dataset.uid }); return; }
    if (act === 'npc-close') { npc = null; market.data = null; render(); return; }
    if (act === 'tl-open') { window.TL.open(); return; }
    if (act === 'friends-open') { friendsUi.open = !friendsUi.open; friendsUi.chat = null; friendsUi.confirm = null; walk = null; render(); $('#view').scrollTop = 0; if (friendsUi.open) loadFriends(); return; }
    if (act === 'friends-close') { friendsUi.open = false; friendsUi.chat = null; render(); return; }
    if (act === 'friend-op') { friendsUi.confirm = null; friendOp(t.dataset.op, { uid: +t.dataset.uid }); return; }
    if (act === 'friend-ask') { friendsUi.confirm = +t.dataset.uid; render(); return; }
    if (act === 'dm-open') { openChat(+t.dataset.uid); return; }
    if (act === 'dm-back') { friendsUi.chat = null; loadFriends(); return; }
    if (act === 'chat-open') { toggleChat(!chatOpen); return; }
    if (act === 'chat-wide') { chatWide = !chatWide; const ov = $('#chat-ov'); if (ov) ov.classList.toggle('open', chatOpen || chatWide); if (chatWide) { const log = $('#chat-log'); if (log) log.scrollTop = log.scrollHeight; } return; }
    if (act === 'menu-back') { menuSec = null; render(); return; }
    if (act === 'travel') { travelTo(t.dataset.to); return; }
    if (act === 'lib-tab') { libUi = { tab: t.dataset.tab2, q: libUi.q, open: null }; render(); return; }
    if (act === 'lib-open') { libUi.open = libUi.open === t.dataset.key ? null : t.dataset.key; libRefresh(); return; }
    if (act === 'lib-go') { libUi = { tab: t.dataset.tab2, q: t.dataset.q, open: null }; const one = LIB[libUi.tab].filter((x) => L.nameMatch([x.name], libUi.q)); if (one.length === 1) libUi.open = { maps: 'map:', monsters: 'mon:', items: 'item:' }[libUi.tab] + one[0].id; render(); return; }
    if (act === 'profile') { openPlayer({ id: +t.dataset.uid }); return; }
    if (act === 'profile-close') { profileUi = { open: false, info: null }; render(); return; }
    // rời hồ sơ khi sang thăm nhà / vào trận
    if (profileUi.open && (act === 'home-visit' || act === 'pvp_challenge')) profileUi = { open: false, info: null };
    if (act === 'notes-open') { notes.open = !notes.open; mail.open = false; walk = null; if (notes.open) { notes.list.forEach((n) => { n.read = true; }); saveNotes(); } render(); $('#view').scrollTop = 0; return; }
    if (act === 'notes-close') { notes.open = false; render(); return; }
    if (act === 'notes-clear') { notes.list = []; saveNotes(); render(); return; }
    if (act === 'mail-open') { mail.open = !mail.open; walk = null; render(); $('#view').scrollTop = 0; if (mail.open) loadMail(); return; }
    if (act === 'mail-close') { mail.open = false; render(); return; }
    if (act === 'fish-cast') { walk = null; castLine(); return; }
    if (act === 'sound-toggle') { Sound.toggle(); render(); return; }
    if (act === 'music-toggle') { Sound.toggleMusic(); render(); return; }
    if (act === 'decor-on' || act === 'decor-off') { decor = { on: act === 'decor-on', pick: null }; walk = null; Map_.setDecorating(decor.on); render(); return; }
    if (act === 'decor-pick') { decor.pick = decor.pick === t.dataset.id ? null : t.dataset.id; render(); return; }
    if (act === 'bestiary-toggle') { bestiaryOpen = !bestiaryOpen; render(); return; }
    if (act === 'guild-open') { guildUi.open = true; guildUi.list = null; guildUi.info = null; render(); $('#view').scrollTop = 0; loadGuild(); return; }
    if (act === 'guild-close') { guildUi.open = false; guildUi.confirm = null; render(); return; }
    if (act === 'guild-ask') { guildUi.confirm = { op: t.dataset.op, uid: t.dataset.uid ? +t.dataset.uid : null, label: t.dataset.label }; render(); return; }
    if (act === 'guild-confirm-no') { guildUi.confirm = null; render(); return; }
    if (act === 'mail-filter') { mail.filter = t.dataset.f; render(); return; }
    if (act === 'mail-delete-read') { if (confirm('Xóa mọi thư đã đọc?')) loadMail('delete_read'); return; }
    if (act === 'guild-war-surrender') { if (confirm('Đầu hàng? Bang địch thắng trận chiến này.')) guildOp('war_surrender'); return; }
    if (act === 'guild-op') { const d = t.dataset; guildOp(d.op, Object.assign({}, d.id ? { id: +d.id } : {}, d.uid ? { uid: +d.uid } : {})); return; }
    if (act === 'chat-to') { const ch = chatChannels(); chatTo = ch[(ch.indexOf(chatTo) + 1) % ch.length]; const f = $('#chat-form'); if (f) f.outerHTML = viewChat().match(/<form id="chat-form"[\s\S]*<\/form>/)[0]; return; }
    if (act === 'fish-reel') { reelIn(); return; }
    if (act === 'boss-yes') { const d = dialog; if (d) step(d.dir, true); return; }
    // ép bước có thể vỡ đồ / ghép mất đồ: hỏi lại trước
    if (act === 'upgrade' && t.dataset.risk === 'destroy' && !confirm(`Ép ${t.dataset.name} thất bại sẽ VỠ món đồ. Vẫn ép?`)) return;
    if (act === 'forge-pick') {
      forgePick = t.dataset.id;
      hideTip();
      if (npc && npcData().role === 'shop') { goTab('map'); return; }
      toast('Mang món này đến Thợ Rèn ở Làng để ép.');
      return;
    }
    if (act === 'discard') {
      const max = +t.dataset.n || 1;
      let n = 1;
      if (max > 1) {
        const a = prompt(`Vứt bao nhiêu ${t.dataset.name}? (1–${max})`, String(max));
        if (a === null) return;
        n = Math.floor(+a);
        if (!(n >= 1 && n <= max)) { toast('Số lượng không hợp lệ.', true); return; }
      } else if (!confirm(`Vứt ${t.dataset.name}? Món đồ sẽ mất hẳn.`)) return;
      hideTip();
      sendCommand({ act: 'discard', id: t.dataset.id, n });
      return;
    }
    if (act === 'chaos' && t.dataset.gear && !confirm(`Ghép thất bại sẽ mất ${itemOf(t.dataset.gear).name} +${upLevel(t.dataset.gear)} cùng nguyên liệu. Vẫn ghép?`)) return;
    sendCommand(command(act, t));
  }

  async function onAuth() {
    if (busy) return;
    const user = $('#auth-user').value.trim(), pass = $('#auth-pass').value;
    if (!user || !pass) { toast('Nhập tên đăng nhập và mật khẩu.', true); return; }
    busy = true;
    try {
      enter(await Net.login(user, pass, authMode === 'register'));
      toast(authMode === 'register' ? 'Đã tạo tài khoản.' : `Xin chào ${Net.username}!`);
    } catch (err) {
      toast(err.msg, true);
    }
    busy = false;
  }

  async function onPassword() {
    if (busy) return;
    busy = true;
    try {
      const r = await Net.changePassword($('#pw-cur').value, $('#pw-new').value);
      P = r.player;
      pwForm = false;
      render();
      toast('Đã đổi mật khẩu. Các thiết bị khác đã bị đăng xuất.');
    } catch (err) {
      toast(err.msg, true);
    }
    busy = false;
  }

  function onSubmit(e) {
    if (e.target.id === 'auth') { e.preventDefault(); onAuth(); return; }
    if (e.target.id === 'pw-form') { e.preventDefault(); onPassword(); return; }
    if (e.target.id === 'chat-form') { e.preventDefault(); onChatSubmit(); return; }
    if (e.target.id === 'adm-lookup') {
      e.preventDefault();
      Net.admin('lookup', { name: $('#adm-name').value }).then((r) => { adm.user = r.user; render(); }).catch((err) => toast(err.msg, true));
      return;
    }
    if (e.target.id === 'adm-gift' || e.target.id === 'adm-gift-all') { e.preventDefault(); onGift(e.target); return; }
    if (e.target.classList.contains('adm-char')) { e.preventDefault(); onCharOp(e.target); return; }
    if (e.target.id === 'guild-create') {
      e.preventDefault();
      const f = new FormData(e.target);
      sendCommand({ act: 'guild_create', name: f.get('name'), tag: f.get('tag') }).then(() => { if (P && P.guild) loadGuild(); });
      return;
    }
    if (e.target.id === 'guild-war-form') {
      e.preventDefault();
      const tag = ($('#war-tag').value || '').trim().toUpperCase();
      if (tag) guildOp('war_declare', { tag });
      return;
    }
    if (e.target.id === 'guild-donate') {
      e.preventDefault();
      const amount = parseInt($('#donate-amount').value, 10);
      sendCommand({ act: 'guild_donate', amount: amount || 0 }).then(loadGuild);
      return;
    }
    if (e.target.id === 'friend-add') {
      e.preventDefault();
      const name = $('#friend-name').value.trim();
      if (name) friendOp('request', { name });
      return;
    }
    if (e.target.id === 'dm-form') {
      e.preventDefault();
      const input = $('#dm-input'), text = input.value.trim(), c = friendsUi.chat;
      if (!text || !c) return;
      input.value = '';
      Net.dm('send', { uid: c.uid, text }).catch((err) => toast(err.msg, true));
      return;
    }
    if (e.target.id === 'trade-add') {
      e.preventDefault();
      const f = new FormData(e.target), id = f.get('item');
      if (e.submitter && e.submitter.name === 'set') { tradeOffer((o) => { o.gold = Math.max(0, parseInt(f.get('gold'), 10) || 0); }); return; }
      if (!id) return;
      if (isGear(id)) tradeOffer((o) => { o.gear.push(id); });
      else tradeOffer((o) => { o.items[id] = (o.items[id] || 0) + Math.max(1, +f.get('count') || 1); });
      return;
    }
    if (e.target.id === 'market-search') { e.preventDefault(); market.q = $('#market-q').value.trim(); market.data = null; render(); return; }
    if (e.target.id === 'market-sell') {
      e.preventDefault();
      const f = new FormData(e.target);
      sendCommand({ act: 'market_sell', id: f.get('item'), count: +f.get('count') || 1, price: +f.get('price') || 0 })
        .then(() => { market.data = null; market.tab = 'mine'; render(); });
      return;
    }
    if (e.target.id === 'guild-search') { e.preventDefault(); guildUi.q = $('#guild-q').value.trim(); loadGuild(); return; }
    if (e.target.id === 'guild-settings') {
      e.preventDefault();
      const f = new FormData(e.target);
      guildOp('settings', { notice: f.get('notice') || '', open: f.get('open') === 'on' });
      return;
    }
    if (e.target.id === 'adm-announce') {
      e.preventDefault();
      Net.admin('announce', { text: $('#adm-text').value }).then(() => { toast('Đã gửi thông báo.'); $('#adm-text').value = ''; }).catch((err) => toast(err.msg, true));
      return;
    }
    if (e.target.id !== 'create') return;
    e.preventDefault();
    const name = $('#hero-name').value.trim();
    if (!name) { toast('Hãy đặt tên cho nhân vật.', true); return; }
    sendCommand({ act: 'create', name, cls: pickCls });
  }

  function start() {
    document.addEventListener('click', onClick);
    document.addEventListener('submit', onSubmit);
    document.addEventListener('keydown', onKey);
    document.addEventListener('pointerdown', (e) => { if (tipAt && !e.target.closest('#itemtip, [data-act="bag-tip"], [data-act="slot-tip"]')) hideTip(); });
    document.addEventListener('dragstart', onDragStart);
    document.addEventListener('dragover', onDragOver);
    document.addEventListener('drop', onDrop);
    document.addEventListener('dragend', () => { dragging = null; document.querySelectorAll('.over').forEach((x) => x.classList.remove('over')); });
    document.addEventListener('pointerdown', onMapTap);
    window.addEventListener('resize', () => Map_.resize());
    Net.onPlayer((p) => { if (!busy) { P = p; refresh(); } });
    Net.onMap((snap) => { Map_.setWorld(snap); Sound.music(musicMood()); refreshPeopleDot(); });
    Net.onChat(onChatMessage);
    Net.onWorldBoss(onWorldBoss);
    Net.onInvasion(onInvasion);
    Net.onNotice((msg) => { toast(msg); note(msg, /hết hạn|từ chối|hủy/.test(msg) ? 'info' : 'good'); Sound.play(/Thành tựu/.test(msg) ? 'achieve' : 'notice'); });
    window.Doll.onReady(() => { if (P) refresh(); });
    Net.onParty((pt) => {
      const had = !!party;
      party = pt;
      if (!pt && chatTo === 'party') chatTo = 'world';
      if (had && !pt) toast('Tổ đội đã tan.');
      if (P && !P.battle && tab === 'map' && !npc) { const el = $('#party-card'); if (el) el.outerHTML = viewParty(); }
    });
    Net.onPartyInvite((m) => {
      if (!m.from) { if (dialog && dialog.type === 'invite') { dialog = null; toast('Lời mời tổ đội đã hết hạn.'); if (P && !P.battle) render(); } return; }
      toast(`${m.name || 'Một người chơi'} mời bạn vào tổ đội.`);
      note(`${m.name || 'Một người chơi'} mời bạn vào tổ đội.`, 'invite');
      Sound.play('mail');
      dialog = { type: 'invite', from: m.from, name: m.name };
      if (P && !P.battle) { if (tab !== 'map') tab = 'map'; render(); }
    });
    Net.onDm(onDm);
    Net.onFriends((msg) => {
      if (msg) { toast(msg); Sound.play('notice'); }
      Net.friends('list').then((r) => { friendsUi.data = r; friendsUi.dm = r.unread; if (friendsUi.open && !friendsUi.chat) render(); else refreshHud(); }).catch(() => {});
    });
    Net.onTrade((t) => {
      const was = trade;
      trade = t;
      if (was && !t && dialog && dialog.type === 'trade') dialog = null;
      if (P && !P.battle) render();
    });
    Net.onPkInvite((inv) => {
      if (inv && inv.to === Net.userId) {
        toast(`${inv.name} mời bạn cược đấu ${fmt(inv.wager)} vàng.`);
        note(`${inv.name} mời bạn cược đấu ${fmt(inv.wager)} vàng.`, 'invite');
        Sound.play('mail');
        dialog = { type: 'pk', inv };
        if (P && !P.battle) { if (tab !== 'map') tab = 'map'; npc = null; }
      } else if (!inv && dialog && dialog.type === 'pk') dialog = null;
      if (P && !P.battle) render();
    });
    if (window.TL) window.TL.init();
    Net.onPkResult((view) => {
      dialog = { type: 'pkResult', view };
      pkNote(view);
      Sound.play('rare');
      pk = null;
      if (P && !P.battle) { if (tab !== 'map') tab = 'map'; npc = null; render(); }
    });
    Net.onTradeRequest((m) => {
      toast(`${m.name || 'Một người chơi'} muốn giao dịch với bạn.`);
      note(`${m.name || 'Một người chơi'} muốn giao dịch với bạn.`, 'invite');
      Sound.play('mail');
      dialog = { type: 'trade', from: m.from, name: m.name };
      if (P && !P.battle) { if (tab !== 'map') tab = 'map'; npc = null; render(); }
    });
    Net.onShared((m) => {
      if (!P || !P.battle || P.battle.over || !P.battle.encounter || P.battle.encounter.shared !== m.key) return;
      P.battle.monster.hp = m.hp;
      sharedN = m.n;
      render();
    });
    Net.onGuild((g) => {
      if (!P) return;
      const before = P.guild;
      P.guild = g;
      if (!g) chatTo = 'world';
      if (!before && g) toast(`Bạn đã vào bang ${g.name}.`);
      if (before && !g) toast('Bạn không còn ở trong bang.');
      if (guildUi.open) loadGuild(); else if (onMenu('guild')) render();
    });
    Net.onMail((n) => {
      const more = n > mail.unread;
      mail.unread = n;
      if (more) { toast('Bạn có thư mới.'); note('Bạn có thư mới trong Hộp thư.', 'mail'); Sound.play('mail'); if (mail.open) loadMail(); }
      if (P && !P.battle) $('#hud').innerHTML = viewHud();
    });
    setInterval(() => { const el = $('#wb-left'); if (el && wb.alive) el.textContent = clock(wb.endsAt - wb.skew - Date.now()); }, 1000);
    Net.onChatHistory((msgs) => { chats = msgs; const log = $('#chat-log'); if (log) { log.innerHTML = chats.map(ovLine).join(''); log.scrollTop = log.scrollHeight; } });
    document.addEventListener('input', (e) => {
      if (e.target.id === 'chat-input') chatDraft = e.target.value;
      if (e.target.id === 'travel-q') { travelQ = e.target.value; const l = $('#travel-list'); if (l) l.innerHTML = travelList(); }
      if (e.target.id === 'lib-q') { libUi.q = e.target.value; libUi.open = null; libRefresh(); }
    });
    document.addEventListener('change', (e) => {
      if (e.target.id === 'volume') { Sound.setVolume(e.target.value / 100); Sound.play('coin'); }
      if (e.target.id === 'music-volume') Sound.setMusicVolume(e.target.value / 100);
      if (e.target.dataset.chaosPick) { chaosPick[e.target.dataset.chaosPick] = e.target.value; render(); }
    });
    Net.onStatus((st, msg) => {
      const bar = $('#netbar');
      bar.hidden = st === 'online';
      // 'version': server vừa cập nhật, giao diện này cũ → trang tự tải lại
      bar.textContent = st === 'version' ? (msg || 'Đã có bản cập nhật, đang tải lại trang...') : 'Mất kết nối, đang kết nối lại…';
    });
    // vào lại sau khi mất mạng: lấy trạng thái mới nhất từ server
    Net.onRejoin((r) => { P = r.player; walk = null; render(); });
    Net.onExpired(() => {
      P = null; npc = null; dialog = null;
      $('#netbar').hidden = true;
      render();
      toast('Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.', true);
    });
    render();
    Net.resume().then(enter).catch((e) => { toast(e.msg, true); enter(null); });
    if (new URLSearchParams(location.search).get('test') === '1') testHook();
  }

  // Hook cho test tự động (e2e/, chỉ bật khi mở trang với `?test=1`): đọc trạng thái thay vì đoán chữ
  // trên màn hình, và gọi thẳng vài thao tác (đi tới ô, gửi lệnh) như người chơi bấm (FEATURE_CATALOG M8).
  // Chỉ dùng được những gì người chơi vẫn làm được; server vẫn kiểm mọi lệnh.
  function testHook() {
    const copy = (x) => (x == null ? null : JSON.parse(JSON.stringify(x)));
    window.__hl = {
      player: () => copy(P),
      userId: () => Net.userId,
      ui: () => ({
        loading, busy, tab, logged: !!Net.username,
        npc: npc && npc.id, dialog: dialog && dialog.type, menu: tab === 'menu' ? menuSec || 'grid' : null,
        trade: trade && trade.status, party: copy(party),
        mail: mail.open, notes: notes.open, unreadNotes: notesUnread(), friends: friendsUi.open, guild: guildUi.open, walking: !!walk,
      }),
      world: () => copy(Map_.world()),
      npcs: (map) => copy(WORLD.maps[map || (P && P.pos.map)].npcs),
      // đi tới ô (x, y) bằng đúng đường đi của người chơi khi chạm vào bản đồ; xong thì trả vị trí
      walkTo: async (x, y) => { await walkTo(x, y); return P && copy(P.pos); },
      step: (dir) => step(dir),
      send: async (cmd) => { await sendCommand(cmd); return copy(P); },
      tab: (id) => goTab(id),
      menu: (sec) => { goTab('menu'); menuSec = sec || null; render(); },
      closeNpc: () => { npc = null; render(); },
      inspect: (uid) => openPlayer({ id: uid }),
    };
  }

  start();
})();

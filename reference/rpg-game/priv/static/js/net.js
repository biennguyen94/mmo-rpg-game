/* Kết nối tới server Phoenix: đăng nhập/đăng ký qua HTTP, rồi mở WebSocket vào
 * kênh "game". Mọi thao tác gửi qua kênh này và server trả về trạng thái mới.
 *
 * Mất mạng thì thư viện Phoenix tự kết nối lại và vào lại kênh; khi đó Net báo trạng thái
 * (onStatus) và gửi trạng thái nhân vật mới nhất (onRejoin). Nếu token đã bị thu hồi
 * (đăng xuất mọi thiết bị, đổi mật khẩu ở nơi khác) thì báo onExpired để về màn đăng nhập. */
(function () {
  const TOKEN_KEY = 'hac-long-token';
  // nhân vật đang chơi (DECISIONS "Nhiều nhân vật"): mã người chơi để lấy vé WebSocket
  const CID_KEY = 'hac-long-cid';
  // nhân vật đang chơi trong tab này (sessionStorage: còn qua F5 / tự tải lại, mất khi đóng tab)
  const PLAY_KEY = 'hac-long-playing';
  const playing = {
    get() { try { const v = +sessionStorage.getItem(PLAY_KEY); return v > 0 ? v : null; } catch (e) { return null; } },
    set(v) { try { if (v) sessionStorage.setItem(PLAY_KEY, String(v)); else sessionStorage.removeItem(PLAY_KEY); } catch (e) { /* bỏ qua */ } },
  };
  const cb = { player: null, map: null, status: null, rejoin: null, expired: null, chat: null, history: null, boss: null, notice: null, mail: null, guild: null, party: null, invite: null, shared: null, trade: null, tradeRequest: null, friends: null, dm: null };
  let socket = null, channel = null, checkTimer = null;

  const store = {
    get() { try { return localStorage.getItem(TOKEN_KEY); } catch (e) { return null; } },
    set(t) { try { if (t) localStorage.setItem(TOKEN_KEY, t); else localStorage.removeItem(TOKEN_KEY); } catch (e) { /* bỏ qua */ } },
    cid() { try { const v = +localStorage.getItem(CID_KEY); return v > 0 ? v : null; } catch (e) { return null; } },
    setCid(v) { try { if (v) localStorage.setItem(CID_KEY, String(v)); else localStorage.removeItem(CID_KEY); } catch (e) { /* bỏ qua */ } },
  };

  async function api(method, path, body, token) {
    const headers = { 'content-type': 'application/json', accept: 'application/json' };
    if (token) headers.authorization = 'Bearer ' + token;
    let res;
    try {
      res = await fetch(path, { method, headers, body: body ? JSON.stringify(body) : undefined });
    } catch (e) {
      throw { msg: 'Không kết nối được máy chủ.' };
    }
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw { status: res.status, msg: data.error || 'Lỗi máy chủ.' };
    return data;
  }

  let closing = false;   // mình chủ động đóng (đăng xuất, đăng nhập lại): không tự nối lại
  let tries = 0, retryTimer = null;

  function close() {
    clearTimeout(checkTimer);
    clearTimeout(retryTimer);
    closing = true;
    const s = socket;
    socket = channel = null;
    if (s) s.disconnect();
  }

  // Mất kết nối một lúc mà chưa vào lại được: hỏi server xem token còn hiệu lực không.
  function scheduleCheck(token) {
    clearTimeout(checkTimer);
    checkTimer = setTimeout(async () => {
      if (closing || channel) return;
      try {
        await api('GET', '/api/me', null, token);
      } catch (e) {
        if (e.status === 401) { Net.logout(true); if (cb.expired) cb.expired(); return; }
      }
      scheduleCheck(token);
    }, 4000);
  }

  // Mở WebSocket bằng vé dùng một lần (`POST /api/ws-ticket`, token đi trong header, không nằm
  // trong URL) rồi vào kênh "game" kèm mã phiên bản giao diện. Vé chỉ dùng được một lần nên tự
  // quản lý việc nối lại (tắt cơ chế nối lại của Phoenix): mất kết nối → lấy vé mới → mở lại →
  // vào lại kênh (onRejoin). Trả về { username, user_id, player } của lần vào đầu tiên.
  function join(token, cid) {
    close();
    closing = false;
    tries = 0;
    return new Promise((resolve, reject) => {
      let joined = false;
      const fail = (err) => { if (!joined) { joined = true; close(); reject(err); } };

      const lost = () => {
        if (closing || !socket) return;
        const s = socket;
        socket = channel = null;
        s.disconnect();
        if (cb.status) cb.status('offline');
        scheduleCheck(token);
        retry();
      };

      const retry = () => {
        clearTimeout(retryTimer);
        tries += 1;
        retryTimer = setTimeout(() => { if (!closing) open(); }, Math.min(1000 * 2 ** Math.min(tries - 1, 4), 15000));
      };

      const open = async () => {
        let ticket;
        try {
          ticket = (await api('POST', '/api/ws-ticket', cid ? { cid } : null, token)).ticket;
        } catch (e) {
          if (closing) return;
          if (e.status === 401) {
            if (!joined) return fail({ msg: 'Phiên đăng nhập đã hết hạn.' });
            Net.logout(true); if (cb.expired) cb.expired(); return;
          }
          if (!joined && tries >= 2) return fail(e);
          return retry();
        }
        if (closing) return;
        const s = new window.Phoenix.Socket('/socket', {
          params: { ticket },
          reconnectAfterMs: () => 24 * 3600 * 1000,
          rejoinAfterMs: () => 24 * 3600 * 1000,
        });
        socket = s;
        s.onOpen(() => { if (socket === s && cb.status) cb.status('online'); });
        s.onError(() => { if (socket === s) lost(); });
        s.onClose(() => { if (socket === s) lost(); });
        s.connect();
        const ch = s.channel('game', { v: window.CLIENT_VERSION });
        channel = ch;
        ch.on('player', (m) => cb.player && cb.player(m.player));
        ch.on('map', (m) => cb.map && cb.map(m));
        ch.on('chat', (m) => cb.chat && cb.chat(m));
        ch.on('chat_history', (m) => cb.history && cb.history(m.messages));
        ch.on('world_boss', (m) => cb.boss && cb.boss(m));
        ch.on('lake', (m) => cb.lake && cb.lake(m));
        ch.on('invasion', (m) => cb.invasion && cb.invasion(m));
        ch.on('notice', (m) => cb.notice && cb.notice(m.msg));
        // tài khoản vừa vào nhân vật khác ở nơi khác: thôi, không tự nối lại
        ch.on('kicked', (m) => { close(); if (cb.kicked) cb.kicked(m.msg); });
        ch.on('mail', (m) => cb.mail && cb.mail(m.unread));
        ch.on('guild', (m) => cb.guild && cb.guild(m.guild));
        ch.on('party', (m) => cb.party && cb.party(m.party));
        ch.on('party_invite', (m) => cb.invite && cb.invite(m));
        ch.on('trade', (m) => cb.trade && cb.trade(m.trade));
        ch.on('friends', (m) => cb.friends && cb.friends(m.msg));
        ch.on('dm', (m) => cb.dm && cb.dm(m));
        ch.on('trade_request', (m) => cb.tradeRequest && cb.tradeRequest(m));
        ch.on('shared', (m) => cb.shared && cb.shared(m));
        // Tiến Lên (Phase 17): bàn bài, chat bàn, hiệu ứng, sảnh đổi
        ch.on('tl', (m) => cb.tl && cb.tl(m));
        ch.on('tl_chat', (m) => cb.tlChat && cb.tlChat(m));
        ch.on('tl_fx', (m) => cb.tlFx && cb.tlFx(m));
        ch.on('tl_lobby', () => cb.tlLobby && cb.tlLobby());
        ch.onError(() => { if (channel === ch) lost(); });
        ch.join()
          .receive('ok', (r) => {
            tries = 0;
            if (!joined) { joined = true; resolve(r); } else if (cb.rejoin) cb.rejoin(r);
          })
          .receive('error', (r) => {
            if (r && r.reason === 'version') { close(); versionReload(r.msg); return; }
            if (!joined) fail({ msg: 'Không vào được game.' }); else lost();
          })
          .receive('timeout', () => { if (!joined) fail({ msg: 'Máy chủ không phản hồi.' }); else lost(); });
      };

      open();
    });
  }

  // Server đã cập nhật, giao diện này cũ: tải lại trang (mỗi phiên bản chỉ tự tải một lần,
  // tránh vòng lặp nếu trang vẫn cũ vì bộ nhớ đệm).
  function versionReload(msg) {
    const key = 'hac-long-reloaded';
    let done = null;
    try { done = sessionStorage.getItem(key); } catch (e) { /* bỏ qua */ }
    if (cb.status) cb.status('version', msg);
    if (done === window.CLIENT_VERSION) return;
    try { sessionStorage.setItem(key, window.CLIENT_VERSION); } catch (e) { /* bỏ qua */ }
    setTimeout(() => location.reload(), 1200);
  }

  // Mã yêu cầu cho lệnh (`rid`): server nhớ kết quả theo mã, gửi lại cùng mã không chạy hai lần.
  let ridSeq = 0;
  const ridBase = Math.random().toString(36).slice(2, 10);
  const nextRid = () => `${ridBase}-${++ridSeq}`;

  // `retry`: hết giờ chờ thì gửi lại đúng payload một lần (chỉ dùng cho lệnh có `rid`, server bỏ qua
  // nếu lần trước đã chạy).
  function push(event, payload, retry) {
    return new Promise((resolve, reject) => {
      if (!channel) return reject({ msg: 'Chưa kết nối.' });
      channel.push(event, payload, 10000)
        .receive('ok', resolve)
        .receive('error', (e) => reject({ msg: (e && e.msg) || 'Lỗi máy chủ.' }))
        .receive('timeout', () => {
          if (retry) push(event, payload, false).then(resolve, reject);
          else reject({ msg: 'Mất kết nối, thử lại.' });
        });
    });
  }

  const Net = {
    username: null,

    // nhân vật của tài khoản (`/api/me`): [{ id, name, cls, level, rebirths, map }], tối đa `maxChars`
    chars: [],
    maxChars: 5,

    // Như MU: mở game (tab / ứng dụng mới) hoặc đăng nhập thì hiện màn chọn nhân vật ({ select: true }); chưa có nhân
    // vật thì vào màn tạo. F5 / trang tự tải lại (server cập nhật, đổi ngôn ngữ) thì vào thẳng nhân vật đang chơi trong
    // tab này. Mất mạng tự nối lại thì không qua đây. `fresh`: vừa đăng nhập (bỏ nhân vật đang chơi của tab).
    async pick(token, username, fresh) {
      const me = await api('GET', '/api/me', null, token);
      Net.username = me.username || username;
      Net.chars = me.characters || [];
      Net.maxChars = me.max_characters || 5;
      if (fresh) playing.set(null);
      if (!Net.chars.length) return Net.enterChar(null);
      const cur = playing.get();
      if (cur && Net.chars.some((c) => c.id === cur)) return Net.enterChar(cur);
      return { select: true, username: Net.username };
    },

    // Vào nhân vật `cid` (null: dòng tài khoản — chưa có nhân vật thì màn tạo nhân vật).
    async enterChar(cid) {
      store.setCid(cid);
      const r = await join(store.get(), cid);
      Net.username = r.username;
      // nhân vật đang chơi của tab (vào màn tạo nhân vật thì cid null: nhớ mã server trả)
      if (r.user_id) { store.setCid(r.user_id); playing.set(r.user_id); }
      return r;
    },

    // Chỗ tạo nhân vật mới rồi vào màn tạo (server: tối đa `maxChars`).
    async newChar() {
      const { cid } = await api('POST', '/api/characters', null, store.get());
      return Net.enterChar(cid);
    },

    // Xóa nhân vật (gõ lại tên + mật khẩu). Trả danh sách nhân vật còn lại.
    async deleteChar(cid, name, password) {
      const r = await api('POST', '/api/characters/delete', { cid, name, password }, store.get());
      Net.chars = r.characters || [];
      if (store.cid() === cid) store.setCid(null);
      return r;
    },

    // Rời nhân vật đang chơi về màn chọn nhân vật.
    async toSelect() {
      close();
      playing.set(null);
      const me = await api('GET', '/api/me', null, store.get());
      Net.chars = me.characters || [];
      Net.maxChars = me.max_characters || 5;
      return { select: true, username: Net.username };
    },

    // Tự đăng nhập bằng token đã lưu. Trả về { username, user_id, player }, { select } hoặc null.
    async resume() {
      const token = store.get();
      if (!token) return null;
      try {
        await api('GET', '/api/me', null, token);
      } catch (e) {
        if (e.status === 401) { store.set(null); return null; }
        throw e;
      }
      return Net.pick(token);
    },

    // `sec`: { question, answer } lúc đăng ký (câu hỏi bảo mật, DECISIONS "Câu hỏi bảo mật")
    async login(username, password, register, sec) {
      const r = await api('POST', register ? '/api/register' : '/api/login', Object.assign({ username, password }, register ? sec : {}));
      store.set(r.token);
      return Net.pick(r.token, r.username, true);
    },

    // Quên mật khẩu: gửi yêu cầu cho quản trị (server luôn trả ok).
    forgot(username, contact) { return api('POST', '/api/forgot', { username, contact }); },

    // Câu hỏi bảo mật của tài khoản: { question: id | null } (null: chưa đặt, gửi yêu cầu cho quản trị như cũ)
    securityQuestion(username) { return api('POST', '/api/question', { username }); },

    // Trả lời đúng câu hỏi bảo mật: đặt mật khẩu mới, đăng nhập luôn (mọi thiết bị khác bị đăng xuất)
    async recover(username, answer, password) {
      const r = await api('POST', '/api/recover', { username, answer, password });
      store.set(r.token);
      store.setCid(null);
      return Net.pick(r.token, r.username, true);
    },

    // Đặt / đổi câu hỏi bảo mật (cần mật khẩu hiện tại); `me()`: câu hỏi đang đặt
    setSecurity(current, question, answer) { return api('POST', '/api/security', { current, question, answer }, store.get()); },
    me() { return api('GET', '/api/me', null, store.get()); },

    // Đăng xuất thiết bị này. `local`: token đã hết hiệu lực, không cần báo server.
    logout(local) {
      const token = store.get();
      if (token && !local) api('POST', '/api/logout', null, token).catch(() => {});
      store.set(null);
      store.setCid(null);
      playing.set(null);
      Net.username = null;
      Net.chars = [];
      close();
    },

    async logoutAll() {
      await api('POST', '/api/logout_all', null, store.get());
      Net.logout(true);
    },

    // Đổi mật khẩu: server thu hồi mọi token cũ, trả token mới cho thiết bị này.
    async changePassword(current, password) {
      const r = await api('POST', '/api/password', { current, password }, store.get());
      store.set(r.token);
      return join(r.token);
    },

    // Gửi một lệnh, nhận { ok, msg, result, player }.
    // Lệnh đi lại không cần `rid` (gửi liên tục, server tự giới hạn tốc độ).
    send(cmd) {
      if (cmd.act === 'move') return push('cmd', cmd);
      return push('cmd', Object.assign({ rid: nextRid() }, cmd), true);
    },

    // Gửi tin nhắn chat thế giới.
    // `to`: 'guild' để chat trong bang, bỏ trống là chat thế giới.
    chat(text, to) { return push('chat', to ? { text, to } : { text }); },

    // Tổ đội: party('invite', { uid }), party('accept'), party('leave')...
    party(op, payload) { return push('party', Object.assign({ op }, payload || {})); },
    // Giao dịch: trade('request', { uid }), trade('accept'), trade('offer', { offer }), trade('ready')...
    trade(op, payload) { return push('trade', Object.assign({ op }, payload || {})); },
    // Lịch sử đồ sát: { history: [...] }.
    slayHistory() { return push('slay_history', {}); },
    // Đồ sát: đánh ngay người chơi cùng bản đồ (không cần đồng ý).
    slay(uid) { return push('slay', { uid }); },
    // Tiến Lên: tl('lobby'), tl('create', { stake, private }), tl('join', { id }), tl('play', { cards })…
    tl(op, payload) { return push('tl', Object.assign({ op }, payload || {})); },
    // Bạn bè: friends('list'), friends('request', { uid } | { name }), accept/decline/remove { uid }.
    friends(op, payload) { return push('friends', Object.assign({ op }, payload || {})); },
    // Tin riêng: dm('history', { uid }), dm('send', { uid, text }).
    dm(op, payload) { return push('dm', Object.assign({ op }, payload || {})); },
    // Đấu trường: điểm của mình, đối thủ gợi ý, bảng xếp hạng. Xem thông tin người chơi khác.
    arena() { return push('arena', {}); },
    // Tìm đối thủ đấu trường theo tên: { found: [{ user_id, name, cls, level, rating }] }
    arenaFind(q) { return push('arena_find', { q: q || '' }); },
    // Chợ: { listings, fee, max }. Rao bán/mua/rút về là lệnh market_sell/market_buy/market_cancel.
    market(q) { return push('market', { q: q || '' }); },
    // Quảng Trường Quỷ: { top: [{ name, score }] } (hôm nay)
    dsTop() { return push('ds_top', {}); },
    inspect(uid) { return push('inspect', { uid }); },

    // Bang hội: guild('list', { q }), guild('info'), guild('join', { id })... (xem GameChannel).
    guild(op, payload) { return push('guild', Object.assign({ op }, payload || {})); },

    // Bảng xếp hạng: { level, kills, dragon, me }.
    leaderboard() { return push('leaderboard', {}); },

    // Chặn / bỏ chặn chat của một người (trả { blocked }); báo cáo một tin nhắn.
    block(uid) { return push('block', { uid }); },
    unblock(uid) { return push('unblock', { uid }); },
    report(id) { return push('report', { id }); },

    // Hộp thư: { mails, unread }. Mở thư/nhận quà là lệnh { act: 'mail_claim', id }.
    mail(op) { return push('mail', op ? { op } : {}); },

    // Lệnh quản trị (chỉ tài khoản quản trị).
    admin(op, payload) { return push('admin', Object.assign({ op }, payload || {})); },
    // Nhân vật thay đổi từ tab/thiết bị khác.
    onPlayer(f) { cb.player = f; },
    // Quái và người chơi trên bản đồ đang đứng thay đổi.
    onMap(f) { cb.map = f; },
    // 'online' | 'offline'
    onStatus(f) { cb.status = f; },
    // Vào lại kênh sau khi mất kết nối: nhận { username, user_id, player } mới nhất.
    onRejoin(f) { cb.rejoin = f; },
    // Token hết hiệu lực (bị đăng xuất từ nơi khác).
    onExpired(f) { cb.expired = f; },
    // Bị đẩy ra vì tài khoản vào nhân vật khác (DECISIONS "Nhiều nhân vật").
    onKicked(f) { cb.kicked = f; },
    // Tin chat mới / các tin gần nhất lúc vào game.
    onChat(f) { cb.chat = f; },
    onChatHistory(f) { cb.history = f; },
    // Trạng thái trùm thế giới; thông báo riêng (vd. nhận thưởng).
    onWorldBoss(f) { cb.boss = f; },
    onLake(f) { cb.lake = f; },
    onInvasion(f) { cb.invasion = f; },
    onNotice(f) { cb.notice = f; },
    // Số thư chưa mở thay đổi (có thư mới, vừa mở thư).
    onMail(f) { cb.mail = f; },
    // Bang của mình vừa đổi (vào, rời, bị đuổi, lên cấp): { id, name, tag, level, role } hoặc null.
    onGuild(f) { cb.guild = f; },
    // Tổ đội đổi / có lời mời vào tổ đội / máu chung của trận đánh cùng đổi.
    onParty(f) { cb.party = f; },
    onPartyInvite(f) { cb.invite = f; },
    onShared(f) { cb.shared = f; },
    // Bảng giao dịch đổi (hoặc null khi xong/hủy) / có người mời giao dịch.
    onTrade(f) { cb.trade = f; },
    onTradeRequest(f) { cb.tradeRequest = f; },
    onTl(f) { cb.tl = f; },
    onTlChat(f) { cb.tlChat = f; },
    onTlFx(f) { cb.tlFx = f; },
    onTlLobby(f) { cb.tlLobby = f; },
    // Danh sách bạn đổi (msg: thông báo hoặc null) / có tin riêng mới (của mình hoặc gửi cho mình).
    onFriends(f) { cb.friends = f; },
    onDm(f) { cb.dm = f; },
  };

  window.Net = Net;
})();

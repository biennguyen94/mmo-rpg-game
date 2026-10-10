// Test hàm thuần của giao diện (priv/static/js/logic.js). Chạy: node --test test/js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const L = createRequire(import.meta.url)('../../priv/static/js/logic.js');

// bản đồ nhỏ: '#' tường, '.' đi được
const grid = ['#####', '#...#', '#.#.#', '#...#', '#####'];
const passable = (x, y) => grid[y] && grid[y][x] === '.';

test('firstStep: đường ngắn nhất, đứng tại chỗ, không có đường', () => {
  assert.equal(L.firstStep(1, 1, 3, 1, passable), 'right');
  assert.equal(L.firstStep(1, 1, 1, 3, passable), 'down');
  assert.equal(L.firstStep(2, 1, 2, 1, passable), null);
  assert.equal(L.firstStep(1, 1, 0, 0, passable), null); // tường
});

test('firstStep: ô đích được đi vào dù bình thường không qua được (đánh quái, NPC)', () => {
  const blocked = new Set(['3,1']);
  const p = (x, y, goal) => passable(x, y) && (goal || !blocked.has(`${x},${y}`));
  assert.equal(L.firstStep(1, 1, 3, 1, p), 'right'); // tới đích (3,1) dù đích bị "chặn"
  assert.equal(L.firstStep(1, 1, 3, 2, p), 'down'); // vòng xuống, không qua (3,1)
});

test('iconForLevel: lấy mức lớn nhất ≤ cấp', () => {
  const m = { 0: 'a.png', 7: 'a7.png', 11: 'a11.png', note: 'bỏ qua' };
  assert.equal(L.iconForLevel(m, 0), 'a.png');
  assert.equal(L.iconForLevel(m, 6), 'a.png');
  assert.equal(L.iconForLevel(m, 9), 'a7.png');
  assert.equal(L.iconForLevel(m, 15), 'a11.png');
  assert.equal(L.iconForLevel({ 5: 'b5.png' }, 3), null);
  assert.equal(L.iconForLevel(undefined, 3), null);
});

test('effLevel / upClass như Engine.effective_level', () => {
  assert.deepEqual([0, 9, 10, 11].map((l) => L.effLevel(l, 10)), [0, 9, 11, 13]);
  assert.deepEqual([6, 7, 9, 11].map(L.upClass), ['', ' up7', ' up9', ' up11']);
});

test('chaosRate như Chaos.rate (cộng theo cấp đồ, có trần)', () => {
  const wing = { rate: 0.1, per_up: 0.05, max_rate: 0.6, gear: { min_up: 5 } };
  assert.equal(L.chaosRate(wing, 5), 0.1);
  assert.ok(Math.abs(L.chaosRate(wing, 9) - 0.3) < 1e-9);
  assert.equal(L.chaosRate(wing, 30), 0.6);
  assert.equal(L.chaosRate({ rate: 0.7 }, 0), 0.7);
});

test('petLevel / tamePrice như Pets', () => {
  assert.deepEqual(L.petLevel(0, 5, 10), { lv: 1, xp: 0, next: 10, from: 0 });
  assert.equal(L.petLevel(10, 5, 10).lv, 2);
  assert.equal(L.petLevel(29, 5, 10).lv, 2);
  assert.equal(L.petLevel(30, 5, 10).lv, 3);
  assert.equal(L.petLevel(99999, 5, 10).next, null);
  assert.equal(L.tamePrice({ level: 7 }, 1000, 100), 1700);
});

test('gom lệnh cộng điểm: không vượt số điểm, mỗi chỉ số một lệnh', () => {
  let pend = {};
  for (const s of ['str', 'str', 'agi', 'str']) pend = L.allocAdd(pend, s, 3) || pend;
  assert.deepEqual(pend, { str: 2, agi: 1 });
  assert.equal(L.allocAdd(pend, 'vit', 3), null);
  assert.deepEqual(L.allocBatches({ ...pend, vit: 0 }), [
    { act: 'alloc', stat: 'str', n: 2 },
    { act: 'alloc', stat: 'agi', n: 1 },
  ]);
});

test('màu tên theo quan hệ: bang địch > đồng đội > cùng bang > người lạ', () => {
  const rel = { party: [7], tag: 'RONG', enemy: 'HO' };
  assert.equal(L.nameRelation({ id: 9, tag: 'HO' }, rel), 'enemy');
  assert.equal(L.nameRelation({ id: 7, tag: 'HO' }, rel), 'enemy');
  assert.equal(L.nameRelation({ id: 7, tag: null }, rel), 'party');
  assert.equal(L.nameRelation({ id: 8, tag: 'RONG' }, rel), 'guild');
  assert.equal(L.nameRelation({ id: 8, tag: 'KHAC' }, rel), 'other');
  assert.equal(L.nameRelation({ id: 9, tag: 'HO', red: true }, rel), 'red');
  assert.equal(L.nameRelation({ id: 8 }, {}), 'other');
  assert.equal(L.nameColor({ id: 8 }), L.nameColor({ id: 8, tag: 'X' }, {}));
});

test('lệnh chat /w /p /g /a', () => {
  const fr = [{ id: 1, name: 'An' }, { id: 2, name: 'An Khang' }];
  assert.deepEqual(L.parseChat('xin chào', 'guild', fr), { to: 'guild', text: 'xin chào' });
  assert.deepEqual(L.parseChat('/p đánh trùm', 'world', fr), { to: 'party', text: 'đánh trùm' });
  assert.deepEqual(L.parseChat('/G họp bang', 'world', fr), { to: 'guild', text: 'họp bang' });
  assert.deepEqual(L.parseChat('/a chào cả làng', 'party', fr), { to: 'world', text: 'chào cả làng' });
  assert.deepEqual(L.parseChat('/w an khang mai đi săn', 'world', fr), { to: 'whisper', uid: 2, name: 'An Khang', text: 'mai đi săn' });
  assert.deepEqual(L.parseChat('/w An ơi', 'world', fr), { to: 'whisper', uid: 1, name: 'An', text: 'ơi' });
  assert.ok(L.parseChat('/w Lạ ơi', 'world', fr).error);
  assert.ok(L.parseChat('/w An', 'world', fr).error);
  assert.ok(L.parseChat('/p', 'world', fr).error);
  assert.ok(L.parseChat('/x hi', 'world', fr).error);
});

test('Thư viện: tìm theo tên không cần dấu', () => {
  assert.equal(L.fold('Chó Rừng Đen'), 'cho rung den');
  assert.ok(L.nameMatch(['Chó Rừng'], 'cho rung'));
  assert.ok(L.nameMatch(['Chó Rừng'], 'RỪNG'));
  assert.ok(L.nameMatch(['Chó Rừng'], ''));
  assert.ok(!L.nameMatch(['Chó Rừng'], 'doi'));
  assert.ok(L.nameMatch(['Dơi Hang', 'Cave Bat'], 'bat'));
});

import { test } from "node:test";
import assert from "node:assert/strict";
import { AllocBatcher, type Timer } from "../src/logic/alloc.js";
import { AutoAttack, approach } from "../src/logic/autoattack.js";
import { bucket, iconPath } from "../src/logic/icons.js";
import { autoSlot, defaultSplit, dragCommand, twoHandConflict, equipSlotFor, equipmentInBag, firstFreeSlot, pickPotion, requirements, shortDesc } from "../src/logic/items.js";
import { NoticeLog, diffPlayer } from "../src/logic/notices.js";
import { CHAT_KEEP, chatLine, parseChat, pushChat } from "../src/logic/chat.js";
import { RidGen, type ChatPayload, type ItemTemplate, type ItemView, type Player } from "../src/net/protocol.js";
import { InterpBuffer, ServerClock } from "../src/state/interp.js";
import { World } from "../src/state/world.js";

const T = (t: Partial<ItemTemplate> & { templateId: string }): ItemTemplate => ({
  name: t.templateId,
  type: "X",
  slot: null,
  stackable: false,
  iconRef: { group: 0, index: 1 },
  buyPrice: 0,
  sellPrice: 0,
  ...t,
});
const templates = new Map<string, ItemTemplate>([
  ["hp", T({ templateId: "hp", potionType: "HP", stackable: true, effect: { hp: 50, mp: 0 }, iconRef: { group: 14, index: 1 } })],
  ["mp", T({ templateId: "mp", potionType: "MP", stackable: true })],
  ["sword", T({ templateId: "sword", slot: "WEAPON", attackMin: 3, attackMax: 7, requirements: { level: 0, strength: 21 }, classes: ["DK"] })],
  ["ring", T({ templateId: "ring", slot: "RING1", hpBonus: 20, iconRef: { custom: "ring" } })],
]);
const item = (id: string, templateId: string, slot: number, quantity = 1): ItemView => ({
  id, serial: id, templateId, quantity, slot, level: 0, durability: null, luck: false, skill: false, excellentOptions: [],
});

test("RidGen: rid khác nhau", () => {
  const g = new RidGen("x");
  assert.equal(g.next(), "x-1");
  assert.equal(g.next(), "x-2");
});

test("pickPotion: stack slot thấp nhất đúng loại (§19.6)", () => {
  const inv = [item("a", "hp", 7, 3), item("b", "mp", 1), item("c", "hp", 2, 1), item("d", "sword", 0)];
  assert.equal(pickPotion(inv, templates, "HP")?.id, "c");
  assert.equal(pickPotion(inv, templates, "MP")?.id, "b");
  assert.equal(pickPotion([item("d", "sword", 0)], templates, "HP"), null);
  assert.deepEqual(equipmentInBag(inv, templates).map((i) => i.id), ["d"]);
});

test("equipSlotFor: vũ khí 5; nhẫn RING1 nếu trống, ngược lại RING2; firstFreeSlot", () => {
  assert.equal(equipSlotFor(templates.get("sword")!, []), 5);
  assert.equal(equipSlotFor(templates.get("ring")!, []), 8);
  assert.equal(equipSlotFor(templates.get("ring")!, [item("r", "ring", 8)]), 9);
  assert.equal(equipSlotFor(templates.get("hp")!, []), null);
  assert.equal(firstFreeSlot([item("a", "hp", 0), item("b", "hp", 2)], 64), 1);
  assert.equal(firstFreeSlot([item("a", "hp", 0)], 1), null);
});

test("mô tả & yêu cầu item", () => {
  assert.equal(shortDesc(templates.get("sword")!), "Tấn công +3~7");
  assert.equal(shortDesc(templates.get("hp")!), "Hồi 50 HP");
  const p = { class: "DK", strength: 20, level: 1 } as unknown as Player;
  assert.deepEqual(requirements(templates.get("sword")!, p), [{ label: "STR", value: 21, ok: false }]);
});

test("AllocBatcher: debounce 200ms, gộp cùng stat thành một alloc, không vượt điểm", () => {
  const sent: [string, number][] = [];
  let fns: { fn: () => void; ms: number; dead: boolean }[] = [];
  const timer: Timer = {
    set: (fn, ms) => {
      const h = { fn, ms, dead: false };
      fns.push(h);
      return h;
    },
    clear: (h) => ((h as { dead: boolean }).dead = true),
  };
  const b = new AllocBatcher((s, p) => sent.push([s, p]), timer);
  assert.ok(b.click("strength", 3));
  assert.ok(b.click("strength", 3));
  assert.ok(b.click("vitality", 3));
  assert.equal(b.click("energy", 3), false);
  assert.equal(b.pendingFor("strength"), 2);
  assert.ok(fns.every((f) => f.ms === 200));
  for (const f of fns) if (!f.dead) f.fn();
  fns = [];
  assert.deepEqual(sent, [["strength", 2], ["vitality", 1]]);
  assert.equal(b.pendingFor("strength"), 0);
});

test("icon: tra icon_map theo bucket + _e, fallback, placeholder", () => {
  assert.deepEqual([0, 4, 9, 20].map(bucket), [0, 3, 9, 15]);
  const map = {
    "0/1": { "0": "items/a0.png", "9e": "items/a9e.png" },
    "14/1": { "0": "placeholder.png" },
    "custom/ring": { "0": "custom/ring.png" },
    _placeholder: "placeholder.png",
  };
  const sword = T({ templateId: "s", iconRef: { group: 0, index: 1 } });
  assert.equal(iconPath(map, sword), "items/a0.png");
  assert.equal(iconPath(map, sword, 9, true), "items/a9e.png");
  assert.equal(iconPath(map, sword, 9, false), "items/a0.png");
  assert.equal(iconPath(map, templates.get("ring")), "custom/ring.png");
  assert.equal(iconPath(map, T({ templateId: "z", iconRef: { group: 5, index: 5 } })), "placeholder.png");
  assert.equal(iconPath(null, sword), "placeholder.png");
});

test("NoticeLog: tối đa 50, chưa đọc, xóa", () => {
  const log = new NoticeLog();
  for (let i = 0; i < 55; i++) log.add("SYSTEM", `n${i}`);
  assert.equal(log.list().length, 50);
  assert.equal(log.list()[0].text, "n54");
  assert.equal(log.unread(), 50);
  log.markAllRead();
  assert.equal(log.unread(), 0);
  log.add("ERROR", "x");
  assert.equal(log.list(true).length, 1);
  log.clear();
  assert.equal(log.list().length, 0);
});

test("diffPlayer: EXP, level up, nhặt đồ, Zen", () => {
  const base = { level: 1, experience: 0, zen: 0, inventory: [] as ItemView[] } as unknown as Player;
  assert.deepEqual(diffPlayer(base, { ...base, experience: 10, zen: 7 }, templates).map((n) => n.type), ["EXP_GAIN", "SYSTEM"]);
  const lv = diffPlayer({ ...base, experience: 95 }, { ...base, level: 2, experience: 5 }, templates);
  assert.deepEqual(lv.map((n) => [n.type, n.sub]), [["LEVEL_UP", "Level 1 → 2"]]);
  const pk = diffPlayer(base, { ...base, inventory: [item("a", "sword", 0)] }, templates);
  assert.deepEqual(pk.map((n) => n.text), ["Nhận: sword"]);
});

test("Interp: nội suy tuyến tính giữa hai mẫu, giữ mẫu cuối, reset khi teleport", () => {
  const b = new InterpBuffer();
  assert.equal(b.at(0), null);
  b.push(1000, 0, 0);
  b.push(1200, 2, 0);
  assert.deepEqual(b.at(1100), { x: 1, y: 0 });
  assert.deepEqual(b.at(900), { x: 0, y: 0 });
  assert.deepEqual(b.at(5000), { x: 2, y: 0 });
  b.push(1100, 9, 9); // gói trễ bị bỏ
  assert.deepEqual(b.at(1200), { x: 2, y: 0 });
  b.reset(1300, 10, 10);
  assert.deepEqual(b.at(1250), { x: 10, y: 10 });
});

test("ServerClock: offset theo snapshot", () => {
  const c = new ServerClock();
  c.observe(10_000, 1_000);
  assert.equal(c.now(1_500), 10_500);
});

test("World: spawn = thêm-hoặc-cập-nhật, snapshot, removed", () => {
  const w = new World();
  w.spawn({ id: "m_1", kind: "monster", x: 1, y: 1, hp: 30, maxHp: 30, state: "idle", name: "Spider", level: 2 }, 0);
  w.spawn({ id: "m_1", kind: "monster", x: 5, y: 5, hp: 30, maxHp: 30, state: "idle", name: "Spider", level: 2 }, 10);
  assert.equal(w.entities.size, 1);
  w.snapshot({ t: 100, entities: [{ id: "m_1", x: 6, y: 5, hp: 20, state: "chase" }, { id: "x", x: 0, y: 0, hp: 0, state: "" }], removed: [] });
  assert.equal(w.entities.get("m_1")?.hp, 20);
  assert.equal(w.entities.has("x"), false);
  w.snapshot({ t: 200, entities: [], removed: ["m_1"] });
  assert.equal(w.entities.size, 0);
});

test("AutoAttack: ngoài tầm → move_to ô kề; trong tầm → đánh theo cooldown; skill lặp lại (P2-M3), NO_MANA → đánh thường; dừng khi quái chết", () => {
  const a = new AutoAttack();
  const me = { x: 0, y: 0 };
  assert.equal(a.tick(0, me, { x: 1, y: 0, alive: true }, 1, 1000), null);
  a.start("m_1", "twisting_slash");
  assert.deepEqual(a.tick(0, me, { x: 5, y: 3, alive: true }, 2, 1000), { act: "move_to", x: 4, y: 2 });
  assert.equal(a.tick(10, me, { x: 5, y: 3, alive: true }, 2, 1000), null); // đã gửi, đang đi
  assert.deepEqual(a.tick(20, { x: 4, y: 2 }, { x: 5, y: 3, alive: true }, 2, 1000), { act: "skill", id: "twisting_slash", target: "m_1" });
  assert.equal(a.tick(500, { x: 4, y: 2 }, { x: 5, y: 3, alive: true }, 1, 1000), null);
  assert.deepEqual(a.tick(1020, { x: 4, y: 2 }, { x: 5, y: 3, alive: true }, 2, 1000), { act: "skill", id: "twisting_slash", target: "m_1" });
  a.skillFailed();
  assert.deepEqual(a.tick(2040, { x: 4, y: 2 }, { x: 5, y: 3, alive: true }, 1, 1000), { act: "attack", target: "m_1" });
  a.retryAfter(1100, 100);
  assert.equal(a.tick(3000, { x: 4, y: 2 }, { x: 5, y: 3, alive: false }, 1, 1000), null);
  assert.equal(a.target, null);
  assert.deepEqual(approach({ x: 0, y: 10 }, { x: 5, y: 5 }), { x: 4, y: 6 });
});

test("dragCommand: kéo thả túi đồ → lệnh (P2-M1)", () => {
  const sword = item("s", "sword", 0);
  const pot = item("p", "hp", 1, 5);
  const ring = item("r", "ring", 8);
  const p = { inventory: [sword, pot] };
  const bag = (slot: number) => ({ kind: "bag" as const, slot });
  const eq = (slot: number) => ({ kind: "equip" as const, slot });
  assert.deepEqual(dragCommand({ kind: "bag", item: sword }, bag(9), p, templates), {
    act: "move_item",
    payload: { itemId: "s", to: { location: "INVENTORY", slot: 9 } },
  });
  assert.equal(dragCommand({ kind: "bag", item: sword }, bag(0), p, templates), null);
  assert.deepEqual(dragCommand({ kind: "bag", item: sword }, eq(5), p, templates), { act: "equip", payload: { itemId: "s", slot: 5 } });
  assert.equal(dragCommand({ kind: "bag", item: sword }, eq(6), p, templates), null);
  assert.equal(dragCommand({ kind: "bag", item: pot }, eq(5), p, templates), null);
  assert.deepEqual(dragCommand({ kind: "bag", item: item("r2", "ring", 3) }, eq(9), p, templates)?.payload, { itemId: "r2", slot: 9 });
  assert.deepEqual(dragCommand({ kind: "bag", item: pot }, { kind: "trash" }, p, templates), {
    act: "drop",
    payload: { itemId: "p" },
    confirm: true,
  });
  // tháo: ô trống → đúng ô; ô có đồ → ô trống thấp nhất
  assert.deepEqual(dragCommand({ kind: "equip", item: ring }, bag(7), p, templates), { act: "unequip", payload: { slot: 8, toSlot: 7 } });
  assert.deepEqual(dragCommand({ kind: "equip", item: ring }, bag(1), p, templates)?.payload, { slot: 8, toSlot: 2 });
  assert.equal(dragCommand({ kind: "equip", item: ring }, { kind: "trash" }, p, templates), null);
  assert.equal(defaultSplit(5), 2);
  assert.equal(defaultSplit(1), 1);
});

test("twoHandConflict: cung khóa khiên và ngược lại (P2-5)", () => {
  const tpl = new Map(templates);
  tpl.set("bow", T({ templateId: "bow", slot: "WEAPON", weaponType: "bow" }));
  tpl.set("shield", T({ templateId: "shield", slot: "SHIELD" }));
  const two = ["bow", "crossbow"];
  const bow = tpl.get("bow")!;
  const shield = tpl.get("shield")!;
  assert.equal(twoHandConflict(bow, 5, [item("s", "shield", 6)], tpl, two), true);
  assert.equal(twoHandConflict(bow, 5, [], tpl, two), false);
  assert.equal(twoHandConflict(shield, 6, [item("b", "bow", 5)], tpl, two), true);
  assert.equal(twoHandConflict(shield, 6, [item("w", "sword", 5)], tpl, two), false);
  assert.equal(twoHandConflict(tpl.get("sword")!, 5, [item("s", "shield", 6)], tpl, two), false);
});

test("chat: /w Tên nội dung = WHISPER, còn lại NORMAL; định dạng dòng; giữ 50 tin (P2-M5)", () => {
  assert.deepEqual(parseChat("  chào cả nhà "), { channel: "NORMAL", text: "chào cả nhà" });
  assert.deepEqual(parseChat("/w Elf01 hello bạn"), { channel: "WHISPER", to: "Elf01", text: "hello bạn" });
  assert.deepEqual(parseChat("/M Elf01 x"), { channel: "WHISPER", to: "Elf01", text: "x" });
  assert.equal(parseChat("/w Elf01"), null);
  assert.equal(parseChat("   "), null);
  const msg = (channel: "NORMAL" | "WHISPER" | "SYSTEM", from: string, to?: string) => ({ channel, from, text: "t", t: 0, to });
  assert.deepEqual(chatLine(msg("NORMAL", "Ann"), "Me"), { cls: "normal", head: "Ann: ", text: "t" });
  assert.equal(chatLine(msg("NORMAL", "Me"), "Me").cls, "me");
  assert.equal(chatLine(msg("WHISPER", "Ann"), "Me").head, "[Mật] Ann: ");
  assert.equal(chatLine(msg("WHISPER", "Me", "Ann"), "Me").head, "[Mật → Ann] ");
  assert.equal(chatLine(msg("SYSTEM", "Hệ thống"), "Me").head, "[Hệ thống] ");
  let log: ChatPayload[] = [];
  for (let i = 0; i < 60; i++) log = pushChat(log, { ...msg("NORMAL", "A"), text: String(i) });
  assert.equal(log.length, CHAT_KEEP);
  assert.equal(log[0].text, "10");
});

test("kho (P3-M3): kéo thả túi ↔ kho → move_item; [Gửi]/[Rút] chọn ô (gộp stack trước)", () => {
  const sword = item("s", "sword", 0);
  const p = { inventory: [sword] };
  const wh = (slot: number) => ({ kind: "wh" as const, slot });
  assert.deepEqual(dragCommand({ kind: "bag", item: sword }, wh(4), p, templates), {
    act: "move_item",
    payload: { itemId: "s", to: { location: "WAREHOUSE", slot: 4 } },
  });
  const stored = item("w", "ring", 4);
  assert.deepEqual(dragCommand({ kind: "wh", item: stored }, { kind: "bag", slot: 2 }, p, templates)?.payload, {
    itemId: "w",
    to: { location: "INVENTORY", slot: 2 },
  });
  assert.deepEqual(dragCommand({ kind: "wh", item: stored }, wh(9), p, templates)?.payload, { itemId: "w", to: { location: "WAREHOUSE", slot: 9 } });
  assert.equal(dragCommand({ kind: "wh", item: stored }, wh(4), p, templates), null);
  assert.equal(dragCommand({ kind: "wh", item: stored }, { kind: "equip", slot: 8 }, p, templates), null);
  assert.equal(dragCommand({ kind: "equip", item: item("r", "ring", 8) }, wh(1), p, templates), null);

  const tpl = new Map(templates);
  tpl.set("hp", { ...templates.get("hp")!, maxStack: 10 });
  const target = [item("a", "hp", 0, 10), item("b", "hp", 3, 4), item("c", "sword", 1)];
  assert.equal(autoSlot(target, 120, item("x", "hp", 7, 2), tpl), 3);
  assert.equal(autoSlot(target, 120, item("y", "sword", 7), tpl), 2);
  assert.equal(autoSlot([item("a", "sword", 0)], 1, item("y", "sword", 7), tpl), null);
});

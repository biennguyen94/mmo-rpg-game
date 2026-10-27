// Hình nhân vật ghép lớp (doll.js): một lớp ảnh tải hỏng (mạng chập chờn) không được biến mọi người dùng lớp đó
// thành hình trần mặc định mãi mãi. Hỏng lần đầu: tự tải lại rồi vẽ đủ đồ; hỏng hẳn: bỏ lớp đó, vẫn vẽ các lớp còn lại.
// Chạy: node e2e/doll.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer } from './lib.mjs';

const R = reporter('doll');
const browser = await launch();
const { page, errors } = await newPlayer(browser, { cls: 'dw' });

// giáp tấm hỏng 2 lần đầu, cung hỏng mọi lần (chưa ai trong trang dùng)
let plate = 0;
await page.route('**/assets/doll/body/bplate_metal1.png*', (r) => (plate++ < 2 ? r.abort() : r.continue()));
await page.route('**/assets/doll/hand1/bow.png*', (r) => r.abort());

const look = { hair: 'hair/brown1', armor: 'body/bplate_metal1', weapon: 'hand1/bow', shield: 'hand2/shield_kite2' };
const plain = { hair: 'hair/brown1', armor: 'body/bplate_metal1', shield: 'hand2/shield_kite2' };
await page.evaluate((l) => window.Doll.url(l), look);
const ok = await page.waitForFunction((l) => window.Doll.url(l).startsWith('data:'), look, { timeout: 20000 }).then(() => true).catch(() => false);
R.check('lớp hỏng được tải lại, hình ghép xong (không kẹt hình trần)', ok && plate >= 3, `plate requests ${plate}`);

// lớp hỏng hẳn (cung) bị bỏ: hình giống hệt hình không cầm cung, nghĩa là giáp / tóc / khiên vẫn được vẽ
const same = await page.evaluate(([a, b]) => window.Doll.url(a).startsWith('data:') && window.Doll.url(a) === window.Doll.url(b), [look, plain]);
R.check('lớp hỏng hẳn bị bỏ, các lớp còn lại vẫn vẽ', same);
R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);

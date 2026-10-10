// Chạy lần lượt mọi kịch bản e2e (không gồm soak), in tổng kết; thoát 1 nếu có kịch bản lỗi.
//   node e2e/run.mjs [url] [thư_mục_ảnh]
// HL_SHOTS_DOCS=1: chép ảnh chọn lọc sang docs/screenshots (cập nhật ảnh trong tài liệu, FEATURE_CATALOG O4).
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const dir = path.dirname(new URL(import.meta.url).pathname);
const args = process.argv.slice(2);
const names = ['smoke', 'social', 'progress', 'admin', 'mobile', 'pk', 'lang', 'people', 'tienlen', 'items', 'ds', 'bc'];
const failed = [];
for (const n of names) {
  console.log(`\n===== ${n} =====`);
  const r = spawnSync(process.execPath, [path.join(dir, `${n}.mjs`), ...args], { stdio: 'inherit' });
  if (r.status !== 0) failed.push(n);
}

// ảnh dùng trong tài liệu: lấy từ lần chạy này
const DOC_SHOTS = {
  'smoke-battle.png': 'e2e-battle.png',
  'smoke-shop.png': 'e2e-shop.png',
  'social-trade.png': 'e2e-trade.png',
  'pk-result.png': 'e2e-pk.png',
  'progress-wardrobe.png': 'e2e-wardrobe.png',
  'progress-forge.png': 'e2e-forge.png',
  'admin-user.png': 'e2e-admin.png',
  'mobile-map.png': 'e2e-mobile-map.png',
  'mobile-battle.png': 'e2e-mobile-battle.png',
};
if (process.env.HL_SHOTS_DOCS === '1') {
  const shots = args[1] || process.env.HL_SHOTS || path.join(dir, 'screenshots');
  const docs = path.join(dir, '..', 'docs', 'screenshots');
  for (const [from, to] of Object.entries(DOC_SHOTS)) {
    const src = path.join(shots, from);
    if (fs.existsSync(src)) fs.copyFileSync(src, path.join(docs, to));
  }
  console.log(`Đã chép ${Object.keys(DOC_SHOTS).length} ảnh sang docs/screenshots.`);
}

console.log(failed.length ? `\nE2E FAIL: ${failed.join(', ')}` : `\nE2E PASS: ${names.length} kịch bản`);
process.exit(failed.length ? 1 : 0);

// Bước sau `tsc` (JS đã ở priv/static/js): chép thư viện trình duyệt từ node_modules sang
// priv/static/vendor (gitignore). Thiếu thư viện chỉ cảnh báo, không lỗi (game view tạm
// bằng Canvas 2D vẫn chạy — docs/OPEN_QUESTIONS.md E7).
import { copyFileSync, existsSync, mkdirSync } from "node:fs";

const out = new URL("../priv/static/vendor/", import.meta.url);
mkdirSync(out, { recursive: true });

const libs = [["node_modules/phaser/dist/phaser.esm.js", "phaser.esm.js"]];
for (const [src, dst] of libs) {
  if (existsSync(src)) {
    copyFileSync(src, new URL(dst, out));
    console.log(`vendor: ${dst}`);
  } else {
    console.warn(`CẢNH BÁO: chưa có ${src} (npm install) — bỏ qua`);
  }
}

// Đồi Sáo Diều (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long"): vẽ icon vật phẩm 32×32 từ SVG game-icons.net (CC BY 3.0,
// ghi tên trong CREDITS.md): bỏ nền đen, tô màu, thêm viền tối cho nổi trên ô túi đồ.
// Chạy: node scripts/sky_svg_icons.cjs <thư_mục_svg> <thư_mục_ra>
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const [src, out] = process.argv.slice(2);
// tệp svg → [tên png, màu chính, màu viền]
const JOBS = [
  ['gi_feather.svg', 'long_hac.png', '#f4f1ea', '#4a5a6a'],
  ['gi_cloud-ring.svg', 'manh_may.png', '#dff1ff', '#3a6a96'],
  ['gi_kite.svg', 'day_dieu_dut.png', '#b8a38a', '#4a3a2a'],
  ['gi_fragmented-meteor.svg', 'manh_sao.png', '#ffd36a', '#7a3a10'],
  ['gi_flute.svg', 'sao_dong.png', '#d39a4a', '#4a2a10'],
];
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 64, height: 64 }, deviceScaleFactor: 1 });
  for (const [f, name, col, edge] of JOBS) {
    let svg = fs.readFileSync(path.join(src, f), 'utf8');
    svg = svg.replace('<path d="M0 0h512v512H0z"/>', '').replace(/fill="#fff"/g, `fill="${col}"`);
    const html = `<html><body style="margin:0;background:transparent"><div style="width:64px;height:64px;filter:drop-shadow(0 0 1.2px ${edge}) drop-shadow(0 0 1.2px ${edge}) drop-shadow(1px 2px 0 rgba(0,0,0,.45))">${svg.replace('<svg ', '<svg width="56" height="56" style="margin:4px" ')}</div></body></html>`;
    await p.setContent(html);
    const buf = await p.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: 64, height: 64 } });
    fs.writeFileSync(path.join(out, name.replace('.png', '@64.png')), buf);
  }
  await b.close();
})();

// Bộ dịch hai ngôn ngữ (priv/static/js/i18n.js): mẫu câu có tên + số, tên đứng riêng, câu chưa dịch giữ tiếng Việt.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';

const I = createRequire(import.meta.url)('../../priv/static/js/i18n.js');

test('mẫu câu: tên và số thay bằng {n}, tên được dịch, đổi thứ tự được', () => {
  I.load({
    names: { 'Thảo Dược': 'Herb', 'Thợ Rèn': 'Blacksmith', 'Làng': 'Village' },
    t: { 'Đã cất {0} ×{1} vào tủ.': 'Stored {0} ×{1} in the wardrobe.', 'Hãy đến gặp {0} ở {1}.': 'Go see the {0} in the {1}.', 'Cần cấp {0}.': 'Requires level {0}.', 'Đóng': 'Close' },
  });
  assert.equal(I.tr('Đã cất Thảo Dược ×2 vào tủ.'), 'Stored Herb ×2 in the wardrobe.');
  assert.equal(I.tr('Hãy đến gặp Thợ Rèn ở Làng.'), 'Go see the Blacksmith in the Village.');
  assert.equal(I.tr(' Cần cấp 17. '), ' Requires level 17. ');
  assert.equal(I.tr('· Đóng'), '· Close');
  assert.equal(I.tr('Thảo Dược'), 'Herb');
  // chưa có mẫu: giữ câu, chỉ đổi tên đã biết
  assert.equal(I.tr('Câu lạ với Thảo Dược'), 'Câu lạ với Herb');
  assert.equal(I.tr('No Vietnamese here 123'), 'No Vietnamese here 123');
});

test('en.json: mọi bản dịch giữ đúng các chỗ {n} của câu gốc', () => {
  const en = JSON.parse(fs.readFileSync(new URL('../../priv/static/i18n/en.json', import.meta.url)));
  const ph = (s) => (s.match(/\{\d+\}/g) || []).sort().join();
  const bad = Object.entries(en.t).filter(([k, v]) => ph(k) !== ph(v));
  assert.deepEqual(bad.slice(0, 5), []);
  assert.ok(Object.keys(en.names).length > 100 && Object.keys(en.t).length > 1000);
});

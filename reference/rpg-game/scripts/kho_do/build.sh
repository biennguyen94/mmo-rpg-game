#!/usr/bin/env bash
# Dựng lại trang "Kho Đồ Hắc Long" từ dữ liệu game hiện tại, xem được ngay ở máy (mở file, không cần server).
#   scripts/kho_do/build.sh            # ghi vào tmp/kho_do/ (đã gitignore)
#   scripts/kho_do/build.sh /đường/dẫn # ghi vào thư mục khác
# Ra: <thư mục>/kho_do.html + <thư mục>/pixel/… (hình bộ Pixel trang dùng). Mở kho_do.html bằng trình duyệt.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:-tmp/kho_do}"
mkdir -p "$OUT"

MIX_ENV=test mix run --no-start scripts/kho_do/export.exs "$OUT/data.json"
python3 scripts/kho_do/build.py "$OUT/data.json" priv/static/assets/pixel_icons.json "$OUT/kho_do.html"

# chép đúng các hình trang dùng (đường dẫn trong kho_do.html.files.json tương đối với priv/static/assets/)
python3 - "$OUT" <<'PY'
import json, os, shutil, sys
out = sys.argv[1]
for rel in json.load(open(os.path.join(out, "kho_do.html.files.json"))):
    dst = os.path.join(out, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(os.path.join("priv/static/assets", rel), dst)
PY

echo "Xong: mở $(cd "$OUT" && pwd)/kho_do.html"

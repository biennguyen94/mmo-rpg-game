#!/usr/bin/env bash
# Mô phỏng cả hành trình một nhân vật (lên cấp → trùm → chuyển sinh → vùng chuyển sinh) và ghi báo cáo.
#   scripts/balance/journey.sh                         # Kiếm Sĩ, 3 lần chuyển sinh
#   scripts/balance/journey.sh --cls elf --rebirths 10 --seed 42 --farm 1000 --csv
#   scripts/balance/journey.sh --cls all --seed 1      # cả 4 lớp + bảng so sánh
# Báo cáo ở tmp/journey/ (đã gitignore). Mọi tùy chọn: mix help hac_long.journey
set -euo pipefail
cd "$(dirname "$0")/../.."
MIX_ENV="${MIX_ENV:-test}" mix hac_long.journey "$@"

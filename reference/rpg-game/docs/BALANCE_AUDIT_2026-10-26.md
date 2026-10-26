# Rà cân bằng toàn game (2026-10-26)

Công cụ: `mix hac_long.journey --cls all --rebirths 10 --seed 1|2|3` (đánh quái, lên cấp, đồ),
`scripts/pvp/tune.exs` (đồ sát cùng mốc), `scripts/pvp/cross.exs` (khác mốc), `scripts/pvp/run.exs` (nhân vật tối đa),
`scripts/pvp/arena.exs` (Đấu trường). Đồ theo mốc: `scripts/pvp/tier_profile.json` (từ hành trình), mốc 10 = tối đa.

## 1. Lên cấp / đánh quái (hành trình 0 → 10 lần chuyển sinh, 3 seed)

| Lớp | Trận (s1 / s2 / s3) | Chết | Trong đó thua trùm / quái khó | Kỷ lục tháp |
|---|---|---|---|---|
| Kiếm Sĩ | 11 336 / 11 459 / 11 227 | 16 / 13 / 17 | 8 / 4 / 12 | 54–56 |
| Phù Thủy | 11 392 / 10 982 / 11 616 | 43 / 19 / 71 | 32 / 18 / 57 | 54–69 |
| Tiên Nữ | 10 940 / 10 765 / 11 067 | 14 / 11 / 10 | 6 / 3 / 4 | 59–63 |
| Đấu Sĩ | 12 066 / 11 552 / 11 511 | 94 / 20 / 25 | 83 / 14 / 15 | 54 |

- Tốc độ lên cấp 4 lớp gần nhau (±6%).
- **Phù Thủy và Đấu Sĩ chết nhiều hơn hẳn**, gần như toàn bộ khi đánh trùm vùng chuyển sinh (Lôi Long Phong Bạo,
  Long Đầm Thực Thi, Cốt Long Thần Ma… thua 75–97% số lần đánh); Kiếm Sĩ / Tiên Nữ ít khi thua.

## 2. Đồ theo cấp

- Vũ khí đạt cấp 47 ngay từ mốc 0 (thưởng hạ trùm lần đầu); **giáp lên chậm** (trung vị cấp 1 ở r0, 12 ở r2, 17 ở r7–r10);
  trang sức kẹt cấp 29 (tối đa có 33).
- Nguyên nhân: `RULES.loot.gear_slots` — vũ khí 38% số món rơi, cả bộ giáp 43% chia 5 ô (≈ 8,6% mỗi ô), khiên 13%
  (lớp cầm 2 vũ khí / cung không dùng), trang sức 6% chia 3 ô (2% mỗi ô).

## 3. Đồ sát cùng mốc (4 lớp đồ ngang nhau) — ĐẠT

r0–r10 lệch 3–9% (`tune.exs`, 48 trận mỗi chiều mỗi cặp). Nhân vật tối đa (`run.exs`): 47 / 58 / 47 / 48%.

## 4. Đồ sát khác mốc

Mốc cao thắng: r1–r0, r3–r2 100%; r5–r4 73%; r7–r6 76%; r9–r8 86%; r10 (tối đa) – r9 100%; chênh ≥ 3 mốc 100%.
Không có luật chặn chênh lệch chuyển sinh (chờ anh chọn).

## 5. Đấu trường — LỆCH

Người thách đấu thắng (trung bình mọi cặp lớp):

| | r0 | r3 | r6 | r10 |
|---|---|---|---|---|
| Có uống bình | 100% | 97% | 99% | 68% |
| Không uống bình | 52% | 88% | 84% | 58% |

- Đối thủ máy (`battle.mirror`) không uống bình → người thách đấu uống bình là thắng chắc.
- Kể cả không bình, người thách đấu vẫn thắng 84–88% ở r3–r6.
- Theo lớp (không bình): Đấu Sĩ 31–36% mọi mốc, Kiếm Sĩ 75% ở r10 — hệ số lớp đang chỉnh cho Đồ sát, Đấu trường khác luật.

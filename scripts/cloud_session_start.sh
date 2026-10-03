#!/bin/bash
# Hook SessionStart cho phiên Claude Code cloud (docs/PROMPT_PHASE1_CLOUD.md §A3).
[ "$CLAUDE_CODE_REMOTE" = "true" ] || exit 0
# VM mặc định latin1 → Elixir cảnh báo; lệnh sau của phiên đọc biến từ CLAUDE_ENV_FILE
export LANG=C.UTF-8 LC_ALL=C.UTF-8
[ -n "$CLAUDE_ENV_FILE" ] && echo 'export LANG=C.UTF-8 LC_ALL=C.UTF-8' >> "$CLAUDE_ENV_FILE"
# Tiến trình nền không được cache: bật lại Postgres mỗi phiên
service postgresql start || true
cd "$CLAUDE_PROJECT_DIR" || exit 0
# Hex/rebar có thể chưa cài trong phiên mới
mix local.hex --force --if-missing >/dev/null 2>&1 || true
mix local.rebar --force --if-missing >/dev/null 2>&1 || true
[ -f mix.exs ] && mix deps.get || true
exit 0

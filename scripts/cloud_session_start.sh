#!/bin/bash
# Hook SessionStart cho phiên Claude Code cloud (docs/PROMPT_PHASE1_CLOUD.md §A3).
[ "$CLAUDE_CODE_REMOTE" = "true" ] || exit 0
# Tiến trình nền không được cache: bật lại Postgres mỗi phiên
service postgresql start || true
cd "$CLAUDE_PROJECT_DIR" || exit 0
[ -f mix.exs ] && mix deps.get || true
exit 0

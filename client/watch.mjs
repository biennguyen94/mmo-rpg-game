// Watcher cho `mix phx.server` (config/dev.exs): chạy `tsc --watch` và dừng nó khi Phoenix đóng
// stdin (tắt server). `tsc --watch` tự nó không thoát khi stdin đóng → sẽ thành tiến trình mồ côi.
import { spawn } from "node:child_process";

const child = spawn("npx", ["--no-install", "tsc", "-p", "tsconfig.json", "--watch", "--preserveWatchOutput"], {
  stdio: ["ignore", "inherit", "inherit"],
  detached: true, // nhóm tiến trình riêng: dừng được cả npx lẫn tsc con của nó
});

const stop = () => {
  try {
    process.kill(-child.pid, "SIGTERM");
  } catch {
    /* đã dừng */
  }
  process.exit(0);
};

process.stdin.on("end", stop);
process.stdin.on("close", stop);
process.stdin.resume();
process.on("SIGTERM", stop);
process.on("SIGINT", stop);
child.on("exit", (code) => process.exit(code ?? 0));

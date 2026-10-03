// Âm thanh tổng hợp bằng Web Audio, không cần file (REUSE từ sound.js của repo nền, KB_BASE_REPO
// §3.4; chỉ giữ hiệu ứng Phase 1). AudioContext chỉ tạo sau thao tác đầu tiên (trình duyệt yêu cầu).

const KEY = "mu.sound";
let ctx: AudioContext | null = null;
let master: GainNode | null = null;
let on = true;
try {
  on = localStorage.getItem(KEY) !== "off";
} catch {
  /* mặc định bật */
}

function audio(): AudioContext | null {
  if (!ctx) {
    const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
    master = ctx.createGain();
    master.gain.value = 0.3;
    master.connect(ctx.destination);
  }
  if (ctx.state === "suspended") void ctx.resume();
  return ctx;
}

interface ToneOpts {
  type?: OscillatorType;
  at?: number;
  to?: number | null;
  vol?: number;
}

function tone(freq: number, dur: number, { type = "square", at = 0, to = null, vol = 0.3 }: ToneOpts = {}): void {
  const c = ctx!;
  const t = c.currentTime + at;
  const o = c.createOscillator();
  const g = c.createGain();
  o.type = type;
  o.frequency.setValueAtTime(freq, t);
  if (to) o.frequency.exponentialRampToValueAtTime(to, t + dur);
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(vol, t + 0.005);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g).connect(master!);
  o.start(t);
  o.stop(t + dur + 0.02);
}

function noise(dur: number, { at = 0, vol = 0.3, freq = 1200, to = null as number | null } = {}): void {
  const c = ctx!;
  const t = c.currentTime + at;
  const len = Math.max(1, Math.floor(c.sampleRate * dur));
  const buf = c.createBuffer(1, len, c.sampleRate);
  const d = buf.getChannelData(0);
  for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
  const src = c.createBufferSource();
  const f = c.createBiquadFilter();
  const g = c.createGain();
  src.buffer = buf;
  f.type = "bandpass";
  f.frequency.setValueAtTime(freq, t);
  if (to) f.frequency.exponentialRampToValueAtTime(to, t + dur);
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  src.connect(f).connect(g).connect(master!);
  src.start(t);
  src.stop(t + dur + 0.02);
}

const notes = (list: number[], gap: number, opts: ToneOpts & { dur: number }) =>
  list.forEach((f, i) => tone(f, opts.dur, { ...opts, at: (opts.at ?? 0) + i * gap }));

const SFX = {
  hit: () => (noise(0.09, { freq: 900, vol: 0.5 }), tone(140, 0.1, { type: "triangle", to: 60, vol: 0.4 })),
  miss: () => noise(0.18, { freq: 500, to: 3000, vol: 0.18 }),
  hurt: () => (tone(110, 0.18, { type: "sawtooth", to: 55, vol: 0.3 }), noise(0.08, { freq: 400, vol: 0.3 })),
  potion: () => notes([520, 660, 780], 0.06, { type: "sine", vol: 0.2, dur: 0.12 }),
  pickup: () => (tone(988, 0.07, { vol: 0.15 }), tone(1319, 0.18, { vol: 0.15, at: 0.07 })),
  levelup: () => notes([523, 659, 784, 1047, 1319], 0.08, { type: "square", vol: 0.13, dur: 0.14 }),
  click: () => tone(1200, 0.03, { type: "square", vol: 0.08 }),
};

export type SoundName = keyof typeof SFX;

export const Sound = {
  play(name: SoundName): void {
    if (!on || !audio()) return;
    try {
      SFX[name]();
    } catch {
      /* âm thanh không bao giờ làm hỏng game */
    }
  },
  get on(): boolean {
    return on;
  },
  set(value: boolean): void {
    on = value;
    try {
      localStorage.setItem(KEY, value ? "on" : "off");
    } catch {
      /* bỏ qua */
    }
  },
};

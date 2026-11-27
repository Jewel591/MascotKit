// 把 Grok Bot 的动作片段换算成 MascotKit 的 motion.json。
//
//   node scripts/import-grok-motion.mjs <Grok 的 motion.js> Sources/MascotKit/Resources/motion.json
//
// Grok 的数据在 social-studio 的 uploads/motion/grok-bot/motion.js（BG_STATES 与 BG_CLIPS），本仓不存副本。
// 关键帧的时间、数值与贝塞尔缓动原样保留，只做单位与坐标换算；哪个状态用哪些片段、叠加哪些附属部件写在本文件里。
// motion.json 是生成物：要改动作，改这里的对应表或换算常量后重新生成，不手改 motion.json。
import { readFileSync, writeFileSync } from "node:fs";

// ---- 换算常量 ----

// Grok 的位移以身体大小为单位、向上为正；Kit 以画布边长的百分之一为单位、向下为正。
const POSITION_SCALE = 50;
// Grok 的整体缩放静止值
const REST_SCALE = 0.6;
// 表情轨里的 blink 是瞬时事件，换成眼睑轨道上的一次闭合
const BLINK_CLOSE = 0.06;
const BLINK_OPEN = 0.1;

// Grok 的表情名对应到 Kit 的表情名
const EXPRESSIONS = {
  neutral: "round", happy: "happy", sad: "worried", surprised: "surprised", confused: "confused",
  strange: "confused", inspect: "focus", inspecting: "focus", calm: "calm", squinted: "squinted", sleepy: "sleepy",
};

// ---- 附属部件 ----
// Grok 用变形指令画的状态专属图形没有关键帧数据，这部分是 Kit 自己的。位置单位为角色设计坐标。

const ORBIT_CENTER = [13, 13];
const ORBIT_RADIUS = [10.5, 3.6];
const ORBIT_ANCHORS = { dot1: [19.8, 6.4], dot2: [21.5, 4.8], dot3: [23.5, 3.1] };

function orbit(duration) {
  const steps = 12;
  const tracks = {};
  Object.entries(ORBIT_ANCHORS).forEach(([name, anchor], index) => {
    const position = [];
    for (let step = 0; step <= steps; step++) {
      const angle = 2 * Math.PI * (step / steps + index / 3);
      position.push({
        t: duration * step / steps,
        v: [ORBIT_CENTER[0] + ORBIT_RADIUS[0] * Math.cos(angle) - anchor[0], ORBIT_CENTER[1] + ORBIT_RADIUS[1] * Math.sin(angle) - anchor[1]],
        ease: "linear",
      });
    }
    tracks[name] = { opacity: [{ t: 0, v: 1 }], position };
  });
  return { duration, attachments: tracks };
}

const OVERLAYS = {
  dots: {
    duration: 3.2,
    attachments: Object.fromEntries([["dot1", 0.3], ["dot2", 0.8], ["dot3", 1.3]].map(([name, at]) => [name, {
      opacity: [{ t: 0, v: 0, ease: "hold" }, { t: at, v: 0, ease: "out" }, { t: at + 0.2, v: 1, ease: "hold" }, { t: 2.6, v: 1 }, { t: 2.9, v: 0 }],
      scale: [{ t: 0, v: [0.4, 0.4], ease: "hold" }, { t: at, v: [0.4, 0.4], ease: "out" }, { t: at + 0.2, v: [1, 1] }],
    }])),
  },
  question: {
    duration: 3.6,
    attachments: { question: {
      opacity: [{ t: 0, v: 1 }],
      rotation: [{ t: 0, v: 8 }, { t: 1.8, v: -4 }, { t: 3.6, v: 8 }],
      position: [{ t: 0, v: [0, 0] }, { t: 1.8, v: [0, -0.5] }, { t: 3.6, v: [0, 0] }],
    } },
  },
  zzz: {
    duration: 4.8,
    attachments: { zzz: {
      opacity: [{ t: 0, v: 0, ease: "linear" }, { t: 0.8, v: 0.9, ease: "hold" }, { t: 3.2, v: 0.9, ease: "linear" }, { t: 4.4, v: 0 }],
      position: [{ t: 0, v: [0, 0], ease: "linear" }, { t: 4.4, v: [1.6, -4] }],
      scale: [{ t: 0, v: [0.6, 0.6], ease: "linear" }, { t: 4.4, v: [1.2, 1.2] }],
      rotation: [{ t: 0, v: -8, ease: "linear" }, { t: 4.4, v: 10 }],
    } },
  },
  spark: {
    duration: 1.1,
    attachments: { spark: {
      opacity: [{ t: 0, v: 0, ease: "hold" }, { t: 0.3, v: 0, ease: "out" }, { t: 0.45, v: 1, ease: "hold" }, { t: 0.9, v: 1, ease: "in" }, { t: 1.1, v: 0 }],
      scale: [{ t: 0, v: [0.3, 0.3], ease: "hold" }, { t: 0.3, v: [0.3, 0.3], ease: "out" }, { t: 0.5, v: [1.15, 1.15] }, { t: 0.7, v: [1, 1], ease: "in" }, { t: 1.1, v: [0.6, 0.6] }],
      rotation: [{ t: 0, v: -30, ease: "hold" }, { t: 0.3, v: -30, ease: "out" }, { t: 1.1, v: 40 }],
      position: [{ t: 0, v: [0, 0], ease: "hold" }, { t: 0.3, v: [0, 0], ease: "out" }, { t: 1.1, v: [2, -3] }],
    } },
  },
};

// ---- 对应表 ----
// Kit 片段名 → Grok 片段、状态自带的表情（Grok 状态指令里的 face）、叠加的附属部件。
// overlay 的 fit 为 true 时把附属部件动画拉伸到片段全长，否则按原速播一次。

const CLIPS = {
  idleA: { from: "Idle_A" },
  idleB: { from: "Idle_B" },
  idleD: { from: "Idle_D" },
  greet: { from: "Done_C" },
  listen: { from: "Idle_D", face: "calm" },
  think: { from: "Idle_B", overlay: "dots", fit: true },
  workA: { from: "Working_A" },
  workB: { from: "Working_B" },
  workC: { from: "Working_C" },
  workD: { from: "Working_D" },
  workE: { from: "Working_E" },
  workF: { from: "Working_F" },
  wait: { from: "Idle_B", overlay: "orbit", fit: true },
  celebrate: { from: "Done_A", face: "happy", overlay: "spark" },
  completedHold: { from: "Idle_B", face: "happy" },
  failedHold: { from: "Blocked_B" },
  happy: { ref: "GB-AN-18", from: "Done_A", face: "happy" },
  confused: { ref: "GB-AN-28", from: "Blocked_A", overlay: "question", fit: true },
  sleep: { from: "Idle_B", face: "sleepy", overlay: "zzz", fit: true },
};

// Kit 状态 → 片段。待机与工作沿用 Grok 的片段清单与顺序；Grok 没有打招呼，取它的「兴奋」。
// ref 是所参考的 GrokBot 状态编号（social-studio 的 mascot-kit.js 里的 GROK_STATES），每个状态必填；
// 一个状态的片段来自两个 Grok 状态时写数组。social-studio 的 tools/mascot.test.mjs 核对片段确实换算自所参考的状态。
const STATES = {
  idle: { ref: "GB-AN-01", loop: ["idleB", "idleB", "idleD", "idleB", "idleA"], still: { clip: "idleB", t: 0 } },
  greeting: { ref: ["GB-AN-19", "GB-AN-01"], enter: "greet", loop: ["idleB", "idleB", "idleD", "idleB", "idleA"], still: { clip: "idleB", t: 0 } },
  listening: { ref: "GB-AN-02", loop: "listen", still: { clip: "listen", t: 0 } },
  thinking: { ref: "GB-AN-03", loop: "think", still: { clip: "think", t: 2.5 } },
  working: { ref: "GB-AN-07", loop: ["workA", "workB", "workC", "workD", "workE", "workF"], still: { clip: "workD", t: 0 } },
  waiting: { ref: "GB-AN-12", loop: "wait", still: { clip: "wait", t: 0 } },
  completed: { ref: ["GB-AN-14", "GB-AN-01"], enter: "celebrate", loop: "completedHold", still: { clip: "completedHold", t: 0 } },
  failed: { ref: "GB-AN-15", loop: "failedHold", still: { clip: "failedHold", t: 0 } },
  happy: { ref: "GB-AN-18", loop: "happy", still: { clip: "happy", t: 0.6 } },
  confused: { ref: "GB-AN-28", loop: "confused", still: { clip: "confused", t: 0.8 } },
  sleeping: { ref: "GB-AN-16", loop: "sleep", still: { clip: "sleep", t: 2 } },
};

// ---- 取样（裁剪到工作区时算边界值）----

function cubic(u, p1, p2) {
  return 3 * (1 - u) * (1 - u) * u * p1 + 3 * (1 - u) * u * u * p2 + u * u * u;
}

function ease([x1, y1, x2, y2], x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  let low = 0, high = 1, u = x;
  for (let i = 0; i < 50; i++) {
    const value = cubic(u, x1, x2);
    if (Math.abs(value - x) < 1e-12) break;
    if (value < x) low = u; else high = u;
    u = (low + high) / 2;
  }
  return cubic(u, y1, y2);
}

function sample(keys, time) {
  if (time <= keys[0].t) return keys[0].v;
  for (let i = 1; i < keys.length; i++) {
    if (time < keys[i].t) {
      const from = keys[i - 1], to = keys[i];
      const progress = ease(from.ease, (time - from.t) / (to.t - from.t));
      return from.v.map((value, k) => value + (to.v[k] - value) * progress);
    }
  }
  return keys[keys.length - 1].v;
}

const round = value => Math.round(value * 1e4) / 1e4;

// 把一条数值轨道裁到 [start, end]，时间改为从 0 起算。第一帧之前保持第一帧的值。
function trim(keys, start, end, convert) {
  const out = [{ t: 0, v: sample(keys, start), ease: [0, 0, 1, 1] }];
  for (const key of keys) {
    if (key.t <= start) { out[0].ease = key.ease; continue; }
    if (key.t >= end) break;
    out.push({ t: key.t - start, v: key.v, ease: key.ease });
  }
  const last = keys[keys.length - 1];
  if (last.t >= end) out.push({ t: end - start, v: sample(keys, end), ease: [0, 0, 1, 1] });
  return out.map(key => ({ t: round(key.t), v: convert(key.v), ease: key.ease.map(round) }));
}

function convertClip(source, { face, overlay, fit }) {
  const start = source.workArea ? source.workArea.start : 0;
  const end = source.workArea ? source.workArea.end : source.duration;
  const duration = round(end - start);
  const from = source.tracks;
  const tracks = {};
  if (from.position) tracks.position = trim(from.position, start, end, ([x, y]) => [round(x * POSITION_SCALE), round(-y * POSITION_SCALE)]);
  if (from.rotation) {
    // Grok 的转动是 [俯仰, 左右转, 平面内]，右手系、向上为正：平面内一轴换成屏幕上的顺时针角度
    tracks.rotation = trim(from.rotation, start, end, ([, , z]) => round(-z));
    tracks.turn = trim(from.rotation, start, end, ([x, y]) => [round(y), round(x)]);
  }
  if (from.scale) tracks.scale = trim(from.scale, start, end, ([v]) => [round(v / REST_SCALE), round(v / REST_SCALE)]);
  if (from.squash) tracks.squash = trim(from.squash, start, end, ([x, y]) => [round(x), round(y)]);
  if (from.lids) tracks.lids = trim(from.lids, start, end, ([v]) => round(v));

  const resting = EXPRESSIONS[face || "neutral"];
  const expression = [{ t: 0, v: resting }];
  const blinks = [];
  for (const key of from.expression || []) {
    const time = round(Math.max(0, key.t - start));
    if (key.t >= end) continue;
    if (key.v === "blink") { blinks.push(time); continue; }
    const value = key.v === "neutral" ? resting : EXPRESSIONS[key.v];
    if (!value) throw new Error("未登记的表情 " + key.v);
    // 导出数据里紧贴片段开头的表情帧（差几毫秒）算作开头，否则第一帧会闪一下静止表情
    if (time < 0.02) expression[0].v = value;
    else if (expression[expression.length - 1].v !== value) expression.push({ t: time, v: value });
  }
  tracks.expression = expression;
  if (blinks.length) {
    if (tracks.lids) throw new Error(source.name + " 同时有眼睑轨道和 blink 事件");
    const lids = [{ t: 0, v: 0, ease: "hold" }];
    for (const time of blinks) {
      if (time + BLINK_CLOSE + BLINK_OPEN > duration) continue;
      if (time > 0) lids.push({ t: time, v: 0, ease: "in" }); else lids[0].ease = "in";
      lids.push({ t: round(time + BLINK_CLOSE), v: 1, ease: "out" }, { t: round(time + BLINK_CLOSE + BLINK_OPEN), v: 0, ease: "hold" });
    }
    tracks.lids = lids;
  }

  const clip = { source: source.name, duration, tracks };
  if (overlay) {
    const spec = overlay === "orbit" ? orbit(duration) : OVERLAYS[overlay];
    const stretch = fit ? duration / spec.duration : 1;
    clip.attachments = Object.fromEntries(Object.entries(spec.attachments).map(([name, own]) => [name,
      Object.fromEntries(Object.entries(own).map(([track, keys]) => [track,
        keys.filter(key => key.t * stretch <= duration).map(key => ({ ...key, t: round(key.t * stretch), v: Array.isArray(key.v) ? key.v.map(round) : key.v }))]))]));
  }
  return clip;
}

const [sourcePath, outputPath] = process.argv.slice(2);
if (!sourcePath || !outputPath) throw new Error("用法：node scripts/import-grok-motion.mjs <Grok 的 motion.js> <motion.json>");
const { BG_CLIPS } = new Function(readFileSync(sourcePath, "utf8") + ";return { BG_CLIPS };")();
const clips = {};
for (const [name, spec] of Object.entries(CLIPS)) {
  const source = BG_CLIPS[spec.from];
  if (!source) throw new Error("Grok 数据里没有片段 " + spec.from);
  clips[name] = convertClip(source, spec);
}
for (const [name, state] of Object.entries(STATES)) if (!state.ref) throw new Error("状态 " + name + " 没有登记参考的 GrokBot 状态编号");
const motion = { formatVersion: 2, generatedBy: "scripts/import-grok-motion.mjs", states: STATES, clips };
writeFileSync(outputPath, JSON.stringify(motion, null, 1) + "\n");
console.log(Object.entries(clips).map(([name, clip]) => name + " " + clip.duration + " 秒").join("\n"));

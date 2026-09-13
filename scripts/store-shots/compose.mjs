#!/usr/bin/env node
// 商店截图合成：原始屏 + captions.json → 各商店尺寸的成品图。
// 规格：docs/specs/2026-09-13-store-assets-design.md §2 §3 §4 §8
//
//   node scripts/store-shots/compose.mjs --end ios     --locale zh-Hans
//   node scripts/store-shots/compose.mjs --end android --locale en-US
//   node scripts/store-shots/compose.mjs --end harmony --locale zh-Hans
//   node scripts/store-shots/compose.mjs --feature --locale zh-Hans
//
// 可选：--out <dir> 改落地目录，--raw <dir> 改原始屏目录（预演用）。
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";
import { stripAlpha, pngSize } from "./png-rgb.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, "../..");
const TEMPLATE = path.join(HERE, "templates", "frame.html");
const FLOW_TEMPLATE = path.join(HERE, "templates", "flow.html");
const CAPTIONS = JSON.parse(fs.readFileSync(path.join(HERE, "captions.json"), "utf8"));
const ICON = path.join(REPO, "docs/design/app-icon-1024-dark-green.png");

// 鸿蒙尺寸：AGC 手机竖版截图规格 1080×1920（9:16），查证记录见 harmony/store/README.md「竖向截图」一行。
// 原始屏是模拟器原生 1256×2760，会等比缩进设备边框里，不按原始屏尺寸出图。
function harmonySize() {
  return { width: 1080, height: 1920, confirmed: true };
}

const ENDS = {
  ios: {
    frame: "ios",
    size: () => ({ width: 1320, height: 2868, confirmed: true }),
    outDir: (locale) => path.join(REPO, "fastlane/screenshots", locale),
    fileName: (shot) => `${shot.n}.png`,
  },
  android: {
    frame: "punch",
    size: () => ({ width: 1080, height: 2400, confirmed: true }),
    outDir: (locale) =>
      locale === "zh-Hans"
        ? path.join(REPO, "android/store/screenshots/phone-1080x2400")
        : path.join(REPO, `android/store/screenshots/phone-1080x2400-${locale}`),
    fileName: (shot) => `${shot.n}-${shot.slug}.png`,
  },
  harmony: {
    frame: "punch",
    size: harmonySize,
    outDir: (locale) => {
      const s = harmonySize();
      const base = path.join(REPO, `harmony/store/screenshots/phone-${s.width}x${s.height}`);
      return locale === "zh-Hans" ? base : `${base}-${locale}`;
    },
    fileName: (shot) => `${shot.n}-${shot.slug}.png`,
  },
};

const SCALE = 2; // 逻辑像素 ×2 → 目标像素，保证 1x 排版数值好看

function parseArgs(argv) {
  const a = { locale: "zh-Hans" };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    if (k === "--feature") a.feature = true;
    else if (k === "--flow") a.flow = true;
    else if (k === "--end") a.end = argv[++i];
    else if (k === "--locale") a.locale = argv[++i];
    else if (k === "--out") a.out = argv[++i];
    else if (k === "--raw") a.raw = argv[++i];
    else if (k === "--help" || k === "-h") a.help = true;
    else throw new Error("未知参数 " + k);
  }
  return a;
}

const USAGE = `用法:
  compose.mjs --end ios|android|harmony --locale zh-Hans|en-US [--out <dir>] [--raw <dir>]
  compose.mjs --feature --locale zh-Hans|en-US [--out <dir>]
  compose.mjs --flow [--raw <dir>] [--out <dir>]

原始屏默认读 scripts/store-shots/raw/<end>/zh-Hans/NN*.png（en-US 复用中文原始屏，只换标题）。`;

/** 取某一端某一语言下这张图的文案（含安卓/鸿蒙第 6 张的覆盖）。 */
function captionFor(shot, end, locale) {
  const base = shot[locale];
  const ov = shot.ends?.[end]?.[locale] ?? {};
  return { title: ov.title ?? base.title, subtitle: ov.subtitle ?? base.subtitle };
}

/** 画面几何：标题区在上，设备边框占画面高度 72% 贴底。 */
function geometry(W, H, rawW, rawH) {
  const deviceH = H * 0.72;
  const bottomGap = H * 0.021;
  const deviceTop = H - deviceH - bottomGap;

  const bezel = Math.round(deviceH * 0.0115);
  let screenH = deviceH - bezel * 2;
  let screenW = screenH * (rawW / rawH);
  let deviceW = screenW + bezel * 2;

  const maxW = W * 0.88;
  if (deviceW > maxW) {
    // 极宽的原始屏：改按宽度定尺寸，宁可矮一点也不变形
    deviceW = maxW;
    screenW = deviceW - bezel * 2;
    screenH = screenW * (rawH / rawW);
  }

  const headerTop = H * 0.052;
  const headerGap = H * 0.016;
  const headerH = deviceTop - headerTop - H * 0.022;

  return {
    header: { top: headerTop, side: W * 0.085, height: headerH, gap: headerGap },
    device: {
      w: deviceW,
      h: screenH + bezel * 2,
      top: deviceTop,
      bezel,
      radius: deviceW * 0.132,
      screenW,
      screenH,
    },
    cutout: {
      // iOS 灵动岛：iPhone 17 Pro Max 上约 125×37pt / 440×956pt
      w: screenW * 0.285,
      h: screenH * 0.0385,
      // 安卓 / 鸿蒙打孔
      d: screenH * 0.0175,
      top: screenH * 0.0125,
    },
    type: {
      titleStart: W * 0.079,
      titleMin: W * 0.044,
      titleMaxLines: 2,
      titleBox: headerH * 0.62,
      subStart: W * 0.0345,
      subMin: W * 0.0225,
      subMaxLines: 2,
      subBox: headerH * 0.3,
    },
  };
}

function dataUrl(file) {
  return "data:image/png;base64," + fs.readFileSync(file).toString("base64");
}

function listRaw(dir) {
  if (!fs.existsSync(dir)) return {};
  const map = {};
  for (const f of fs.readdirSync(dir).sort()) {
    const m = /^(\d{2})[-.]/.exec(f) || /^(\d{2})\.png$/.exec(f);
    if (m && f.toLowerCase().endsWith(".png")) map[m[1]] ??= path.join(dir, f);
  }
  return map;
}

async function shoot(page, W, H, payload) {
  const info = await page.evaluate((p) => window.render(p), payload);
  if (info.headerOverflow) throw new Error("标题区溢出：" + payload.title);
  if (info.titleLines > payload.type.titleMaxLines) {
    throw new Error(`主标题 ${info.titleLines} 行，超过 ${payload.type.titleMaxLines} 行：` + payload.title);
  }
  if (info.headerBottom > info.deviceTop + 1) throw new Error("标题压到设备边框：" + payload.title);
  const buf = await page.screenshot({ type: "png", clip: { x: 0, y: 0, width: W, height: H } });
  return { buf: stripAlpha(buf), info };
}

async function runShots(args) {
  const end = ENDS[args.end];
  if (!end) throw new Error("--end 只能是 ios / android / harmony");
  if (!CAPTIONS.locales.includes(args.locale)) throw new Error("--locale 只能是 " + CAPTIONS.locales.join(" / "));

  const size = end.size();
  const rawDir = args.raw ? path.resolve(args.raw) : path.join(HERE, "raw", args.end, "zh-Hans");
  const outDir = args.out ? path.resolve(args.out) : end.outDir(args.locale);
  const raws = listRaw(rawDir);
  const missing = CAPTIONS.shots.filter((s) => !raws[s.n]).map((s) => s.n);
  if (missing.length) throw new Error(`原始屏缺 ${missing.join(",")}（目录 ${rawDir}）`);

  const W = size.width / SCALE;
  const H = size.height / SCALE;

  const browser = await chromium.launch();
  const page = await browser.newPage({
    viewport: { width: Math.round(W), height: Math.round(H) },
    deviceScaleFactor: SCALE,
  });
  await page.goto("file://" + TEMPLATE);

  const jobs = CAPTIONS.shots.map((s) => {
    const raw = raws[s.n];
    const px = pngSize(fs.readFileSync(raw));
    const g = geometry(W, H, px.width, px.height);
    const cap = captionFor(s, args.end, args.locale);
    return { shot: s, raw, px, g, cap, url: dataUrl(raw) };
  });

  // 第一遍只量：同一端同一语言用同一个字号，8 张排版才齐
  let titleSize = Infinity;
  let subSize = Infinity;
  for (const j of jobs) {
    const m = await page.evaluate((p) => window.measure(p), {
      locale: args.locale, frame: end.frame, mode: "shot",
      title: j.cap.title, subtitle: j.cap.subtitle, shot: j.url,
      header: j.g.header, device: j.g.device, cutout: j.g.cutout, type: j.g.type,
    });
    titleSize = Math.min(titleSize, m.titleSize);
    subSize = Math.min(subSize, m.subSize);
  }

  fs.mkdirSync(outDir, { recursive: true });
  const written = [];
  for (const j of jobs) {
    const payload = {
      locale: args.locale, frame: end.frame, mode: "shot",
      title: j.cap.title, subtitle: j.cap.subtitle, shot: j.url,
      header: j.g.header, device: j.g.device, cutout: j.g.cutout,
      type: { ...j.g.type, titleSize, subSize },
    };
    const { buf, info } = await shoot(page, W, H, payload);
    const dest = path.join(outDir, end.fileName(j.shot));
    fs.writeFileSync(dest, buf);
    written.push({ dest, info, raw: j.raw, px: j.px });
    console.log(
      `  ${j.shot.n} ${path.relative(REPO, dest)}  ← ${path.relative(REPO, j.raw)} (${j.px.width}×${j.px.height})  ` +
        `标题 ${info.titleLines} 行 / 副题 ${info.subLines} 行`
    );
  }
  await browser.close();

  console.log(
    `\n${args.end} / ${args.locale}：${written.length} 张 → ${path.relative(REPO, outDir)}` +
      `  目标 ${size.width}×${size.height}${size.confirmed ? "" : "（尺寸待核）"}` +
      `  字号 主 ${titleSize.toFixed(1)} / 副 ${subSize.toFixed(1)} 逻辑 px`
  );
  return written;
}

async function runFeature(args) {
  const W = 1024 / SCALE;
  const H = 500 / SCALE;
  const cap = CAPTIONS.feature[args.locale];
  if (!cap) throw new Error("feature 文案缺 " + args.locale);
  const outDir = args.out ? path.resolve(args.out) : path.join(REPO, "android/store");
  const dest = path.join(outDir, `feature-graphic-1024x500-${args.locale === "zh-Hans" ? "zh" : "en"}.png`);

  const browser = await chromium.launch();
  const page = await browser.newPage({
    viewport: { width: W, height: H },
    deviceScaleFactor: SCALE,
  });
  await page.goto("file://" + TEMPLATE);
  await page.evaluate((p) => window.render(p), {
    locale: args.locale, frame: "punch", mode: "feature",
    title: cap.title, subtitle: cap.subtitle, icon: dataUrl(ICON),
    type: { titleSize: W * 0.082, subSize: W * 0.036 },
  });
  const fit = await page.evaluate(() => {
    const t = document.getElementById("feature-title");
    const s = document.getElementById("feature-sub");
    const box = document.getElementById("feature-text");
    // 主标题不换行，副题不许溢出容器
    let size = parseFloat(getComputedStyle(s).fontSize);
    while (size > 10 && s.scrollWidth > box.clientWidth + 1) {
      size -= 0.5;
      s.style.fontSize = size + "px";
    }
    return {
      titleOverflow: t.scrollWidth > box.clientWidth + 1,
      subOverflow: s.scrollWidth > box.clientWidth + 1,
      subSize: size,
    };
  });
  if (fit.titleOverflow || fit.subOverflow) throw new Error("宣传图文字溢出");
  const buf = stripAlpha(await page.screenshot({ type: "png", clip: { x: 0, y: 0, width: W, height: H } }));
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(dest, buf);
  await browser.close();
  console.log(`宣传图 ${args.locale} → ${path.relative(REPO, dest)}  1024×500`);
  return [{ dest }];
}

// 微信开放平台「应用运营流程图」：官方定义是「App 装到手机后运行起来的界面截图」，
// 所以这里拼的是安卓真机截图串，不是框图。步骤顺序见 §6。
const FLOW_STEPS = [
  { n: "08", text: "选择项目" },
  { n: "01", text: "现场拍摄" },
  { n: "03", text: "排队上传" },
  { n: "04", text: "按项目归档" },
  { n: "07", text: "桌面端落盘" },
];

async function runFlow(args) {
  const rawDir = args.raw ? path.resolve(args.raw) : path.join(HERE, "raw", "android", "zh-Hans");
  const raws = listRaw(rawDir);
  const missing = FLOW_STEPS.filter((s) => !raws[s.n]).map((s) => s.n);
  if (missing.length) throw new Error(`原始屏缺 ${missing.join(",")}（目录 ${rawDir}）`);

  const outDir = args.out ? path.resolve(args.out) : path.join(REPO, "android/store/wechat-open");
  const dest = path.join(outDir, "operation-flow-screens.png");

  // 目标宽 2400 像素 → 逻辑 1200 @×2。左右内边距 34、箭头各 40，其余匀给 5 张截图。
  const W = 2400 / SCALE;
  const pad = 34;
  const arrowW = 40;
  const shotW = Math.floor((W - pad * 2 - arrowW * 4) / 5);
  const px = pngSize(fs.readFileSync(raws[FLOW_STEPS[0].n]));
  const shotH = Math.round(shotW * (px.height / px.width)); // 按原始屏比例，不拉伸

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: W, height: 800 }, deviceScaleFactor: SCALE });
  await page.goto("file://" + FLOW_TEMPLATE);
  const box = await page.evaluate((p) => window.renderFlow(p), {
    shotW, shotH, arrowW,
    steps: FLOW_STEPS.map((s) => ({ text: s.text, src: dataUrl(raws[s.n]) })),
  });
  await page.setViewportSize({ width: W, height: box.height });
  const buf = stripAlpha(
    await page.screenshot({ type: "png", clip: { x: 0, y: 0, width: box.width, height: box.height } })
  );
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(dest, buf);
  await browser.close();
  console.log(
    `运行流程图 → ${path.relative(REPO, dest)}  ${box.width * SCALE}×${box.height * SCALE}  ` +
      `${(buf.length / 1024 / 1024).toFixed(2)} MB  ← ` +
      FLOW_STEPS.map((s) => s.n).join(" → ")
  );
  return [{ dest }];
}

const args = parseArgs(process.argv.slice(2));
if (args.help || (!args.feature && !args.flow && !args.end)) {
  console.log(USAGE);
  process.exit(args.help ? 0 : 1);
}
await (args.flow ? runFlow(args) : args.feature ? runFeature(args) : runShots(args));

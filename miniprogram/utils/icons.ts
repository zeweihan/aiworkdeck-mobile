/**
 * 图标 —— 一律 SVG，绝不用 emoji。
 *
 * 线性描边风格（Lucide 口径），1.75 描边宽，圆角端点。
 * 用 data URI 内联，不走网络、不占包体的独立文件数。
 */

const svg = (body: string, stroke: string, size = 24): string => {
  const raw =
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="${size}" height="${size}" ` +
    `fill="none" stroke="${stroke}" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">` +
    body +
    '</svg>'
  return 'data:image/svg+xml,' + encodeURIComponent(raw)
}

const P = {
  camera:
    '<path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3z"/>' +
    '<circle cx="12" cy="13" r="3.5"/>',
  mic:
    '<path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"/>' +
    '<path d="M19 10v2a7 7 0 0 1-14 0v-2"/><path d="M12 19v3"/>',
  chevronRight: '<path d="m9 18 6-6-6-6"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  upload: '<path d="M12 19V5"/><path d="m5 12 7-7 7 7"/>',
  monitor:
    '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8"/><path d="M12 17v4"/>',
  folder: '<path d="M4 20a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2z"/>',
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>',
}

// 原样写 '#'，交给下面的 encodeURIComponent 编码。
// 别在这里预先写成 '%23'——会被二次编码成 '%2523'，图标全部不显示。
const NAVY = '#1E3A8A'
const SLATE = '#475569'
const WHITE = '#FFFFFF'
const AMBER = '#B45309'
const GREEN = '#15803D'
const FAINT = '#94A3B8'

export const Icon = {
  cameraWhite: svg(P.camera, WHITE, 28),
  micNavy: svg(P.mic, NAVY, 28),
  chevron: svg(P.chevronRight, SLATE, 20),
  chevronFaint: svg(P.chevronRight, FAINT, 18),
  checkGreen: svg(P.check, GREEN, 18),
  uploadNavy: svg(P.upload, NAVY, 18),
  uploadAmber: svg(P.upload, AMBER, 18),
  monitorNavy: svg(P.monitor, NAVY, 18),
  monitorSlate: svg(P.monitor, SLATE, 18),
  folderSlate: svg(P.folder, SLATE, 20),
  shieldNavy: svg(P.shield, NAVY, 18),
}

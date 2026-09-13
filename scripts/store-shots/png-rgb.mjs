// 把 Chromium 截出来的 RGBA PNG 重编码成不带 alpha 通道的 RGB PNG。
// App Store 拒收带透明通道的截图（见 docs/specs/2026-09-13-store-assets-design.md §8）。
// 只处理 8 位、非隔行的 PNG——也就是 Playwright 的输出，别拿它当通用解码器。
import zlib from "node:zlib";

const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

function chunk(type, data) {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, "ascii");
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

function parse(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error("不是 PNG");
  let pos = 8;
  let ihdr = null;
  const idat = [];
  while (pos + 8 <= buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString("ascii", pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      ihdr = {
        w: data.readUInt32BE(0),
        h: data.readUInt32BE(4),
        depth: data[8],
        color: data[9],
        interlace: data[12],
      };
    } else if (type === "IDAT") idat.push(Buffer.from(data));
    else if (type === "IEND") break;
    pos += 12 + len;
  }
  if (!ihdr) throw new Error("PNG 缺 IHDR");
  return { ihdr, idat: Buffer.concat(idat) };
}

function unfilter(raw, w, h, bpp) {
  const stride = w * bpp;
  const out = Buffer.alloc(h * stride);
  let p = 0;
  for (let y = 0; y < h; y++) {
    const f = raw[p++];
    const base = y * stride;
    const pbase = base - stride;
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? out[base + x - bpp] : 0;
      const b = y > 0 ? out[pbase + x] : 0;
      const c = y > 0 && x >= bpp ? out[pbase + x - bpp] : 0;
      let v = raw[p + x];
      switch (f) {
        case 0: break;
        case 1: v += a; break;
        case 2: v += b; break;
        case 3: v += (a + b) >> 1; break;
        case 4: v += paeth(a, b, c); break;
        default: throw new Error("未知 PNG 行过滤器 " + f);
      }
      out[base + x] = v & 0xff;
    }
    p += stride;
  }
  return out;
}

function encodeRgb(rgb, w, h) {
  const stride = w * 3;
  const rows = Buffer.alloc(h * (stride + 1));
  let o = 0;
  for (let y = 0; y < h; y++) {
    rows[o++] = 4; // Paeth：照片 + 渐变底用它压得最小
    const base = y * stride;
    const pbase = base - stride;
    for (let x = 0; x < stride; x++) {
      const a = x >= 3 ? rgb[base + x - 3] : 0;
      const b = y > 0 ? rgb[pbase + x] : 0;
      const c = y > 0 && x >= 3 ? rgb[pbase + x - 3] : 0;
      rows[o++] = (rgb[base + x] - paeth(a, b, c)) & 0xff;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 2;   // color type 2 = truecolour，无 alpha
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(rows, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

/** 输入任意 8 位非隔行 PNG，输出 color type 2（无 alpha）的 PNG。 */
export function stripAlpha(buf) {
  const { ihdr, idat } = parse(buf);
  if (ihdr.depth !== 8 || ihdr.interlace !== 0) {
    throw new Error(`只支持 8 位非隔行 PNG（depth=${ihdr.depth} interlace=${ihdr.interlace}）`);
  }
  if (ihdr.color === 2) return buf; // 已经没有 alpha
  if (ihdr.color !== 6) throw new Error("只支持 color type 2/6，收到 " + ihdr.color);

  const { w, h } = ihdr;
  const rgba = unfilter(zlib.inflateSync(idat), w, h, 4);
  const rgb = Buffer.alloc(w * h * 3);
  for (let i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
    rgb[j] = rgba[i];
    rgb[j + 1] = rgba[i + 1];
    rgb[j + 2] = rgba[i + 2];
  }
  return encodeRgb(rgb, w, h);
}

/** 只读 IHDR，拿原始屏的像素宽高（合成时要用它算设备边框比例）。 */
export function pngSize(buf) {
  const { ihdr } = parse(buf);
  return { width: ihdr.w, height: ihdr.h };
}

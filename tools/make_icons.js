// Genera los PNG del logo (icono de app, icono adaptativo y splash) sin
// dependencias: rasteriza las formas del logo "hueco en la agenda" con
// supermuestreo y escribe PNG con zlib de Node.
//
//   node tools/make_icons.js
//
// Salida en bookingnow_app/assets/icon y assets/splash. Después:
//   cd bookingnow_app && dart run flutter_launcher_icons && dart run flutter_native_splash:create
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const TEAL = [0x0d, 0x94, 0x88];
const TEAL_DEEP = [0x13, 0x4e, 0x4a];
const AMBER = [0xf5, 0x9e, 0x0b];
const WHITE = [255, 255, 255];

// ---------- PNG ----------
const crcTable = new Int32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c;
});
const crc32 = (buf) => {
  let c = -1;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
};
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function writePng(file, w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0)),
  ]);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, png);
  console.log(`${path.relative(process.cwd(), file)}  ${w}x${h}`);
}

// ---------- Formas (coordenadas en la caja 56x56 del logo) ----------
const sdRoundRect = (px, py, x, y, w, h, r) => {
  const qx = Math.abs(px - (x + w / 2)) - (w / 2 - r);
  const qy = Math.abs(py - (y + h / 2)) - (h / 2 - r);
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
};
const sdCircle = (px, py, cx, cy, r) => Math.hypot(px - cx, py - cy) - r;

/** Capas del logo: [sdf(px,py), color, alpha] en orden de pintado. */
function logoLayers({ background, bgColor = TEAL, bgRadius = 16, barColor = WHITE }) {
  const layers = [];
  if (background) layers.push([(x, y) => sdRoundRect(x, y, 0, 0, 56, 56, bgRadius), bgColor, 1]);
  layers.push([(x, y) => sdRoundRect(x, y, 13, 15, 30, 6, 3), barColor, 0.45]);
  layers.push([(x, y) => sdRoundRect(x, y, 13, 25, 30, 6, 3), barColor, 1]);
  layers.push([(x, y) => sdRoundRect(x, y, 13, 35, 30, 6, 3), barColor, 0.45]);
  layers.push([(x, y) => sdCircle(x, y, 40, 28, 5.5), AMBER, 1]);
  return layers;
}

/**
 * Rasteriza en un lienzo size×size. `scale` = píxeles por unidad de logo,
 * `offset` = desplazamiento en píxeles del origen del logo. `fill` = color de
 * fondo opaco del lienzo (o null para transparente). `gradient` dibuja un
 * degradado teal diagonal de fondo.
 */
function render(size, layers, { scale, offset, fill = null, gradient = false }) {
  const SS = 4; // supermuestreo 4x4
  const out = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      if (fill) { [r, g, b] = fill; a = 1; }
      if (gradient) {
        const t = (x + y) / (2 * size);
        r = TEAL[0] + (TEAL_DEEP[0] - TEAL[0]) * t;
        g = TEAL[1] + (TEAL_DEEP[1] - TEAL[1]) * t;
        b = TEAL[2] + (TEAL_DEEP[2] - TEAL[2]) * t;
        a = 1;
      }
      for (const [sdf, color, alpha] of layers) {
        let cov = 0;
        for (let sy = 0; sy < SS; sy++) {
          for (let sx = 0; sx < SS; sx++) {
            const px = (x + (sx + 0.5) / SS - offset) / scale;
            const py = (y + (sy + 0.5) / SS - offset) / scale;
            if (sdf(px, py) <= 0) cov++;
          }
        }
        cov = (cov / (SS * SS)) * alpha;
        if (cov === 0) continue;
        // composición "over"
        const na = cov + a * (1 - cov);
        r = (color[0] * cov + r * a * (1 - cov)) / na;
        g = (color[1] * cov + g * a * (1 - cov)) / na;
        b = (color[2] * cov + b * a * (1 - cov)) / na;
        a = na;
      }
      const i = (y * size + x) * 4;
      out[i] = Math.round(r); out[i + 1] = Math.round(g); out[i + 2] = Math.round(b); out[i + 3] = Math.round(a * 255);
    }
  }
  return out;
}

const root = path.resolve(__dirname, "..", "bookingnow_app", "assets");

// 1. Icono principal (iOS / Android legacy / web): 1024, fondo degradado a sangre
{
  const size = 1024;
  writePng(path.join(root, "icon", "icon.png"), size, size,
    render(size, logoLayers({ background: false }), { scale: size / 56, offset: 0, gradient: true }));
}
// 2. Icono adaptativo Android: primer plano transparente, logo en la zona segura (66 %)
{
  const size = 1024, inner = size * 0.62;
  writePng(path.join(root, "icon", "icon_foreground.png"), size, size,
    render(size, logoLayers({ background: false }), { scale: inner / 56, offset: (size - inner) / 2 }));
}
// 3. Splash: logo blanco sobre transparente (el fondo lo pone flutter_native_splash)
{
  const size = 768, inner = 480;
  writePng(path.join(root, "splash", "splash_logo.png"), size, size,
    render(size, logoLayers({ background: false }), { scale: inner / 56, offset: (size - inner) / 2 }));
}
// 4. Splash Android 12: icono dentro de círculo (contenido en el 2/3 central)
{
  const size = 1152, inner = 560;
  writePng(path.join(root, "splash", "splash_logo_a12.png"), size, size,
    render(size, logoLayers({ background: false }), { scale: inner / 56, offset: (size - inner) / 2 }));
}
// 5. Logo con fondo redondeado para README / web (512)
{
  const size = 512;
  writePng(path.join(root, "icon", "logo_rounded.png"), size, size,
    render(size, logoLayers({ background: true }), { scale: size / 56, offset: 0 }));
}

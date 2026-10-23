const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

// Loaded on first render — requiring sharp/ffmpeg-static at module load
// makes `firebase deploy` miss the 10s discovery timeout.
let _sharp;
let _ffmpegPath;
function sharp(...args) {
  if (!_sharp) _sharp = require('sharp');
  return _sharp(...args);
}
function ffmpegBin() {
  if (!_ffmpegPath) {
    _ffmpegPath = require('ffmpeg-static');
    try {
      fs.chmodSync(_ffmpegPath, 0o755);
    } catch (_) {}
  }
  return _ffmpegPath;
}

const W = 720;
const H = 1280;
const END_SECONDS = 3;
const ORANGE = '#FF8A00';
const ORANGE_DEEP = '#E86A00';
const INK = '#1B1E28';
const MUTED = '#6B7080';
const BG = '#F6F7FB';

const ASSETS = path.join(__dirname, 'assets');
const FONT_BOLD = path.join(ASSETS, 'fonts', 'Roboto-Bold.ttf');
const FONT_MEDIUM = path.join(ASSETS, 'fonts', 'Roboto-Medium.ttf');
const FONT_BLACK = path.join(ASSETS, 'fonts', 'Roboto-Black.ttf');
const LOGO = path.join(ASSETS, 'logo_mark.png');

function escapeMarkup(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function handleFor(name) {
  const h = String(name || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '')
    .slice(0, 24);
  return h ? `@${h}` : '@vero360';
}

function fontFaceCss(family, fontfile) {
  if (!fontfile || !fs.existsSync(fontfile)) return '';
  const b64 = fs.readFileSync(fontfile).toString('base64');
  return `@font-face{font-family:'${family}';src:url('data:font/ttf;base64,${b64}');}`;
}

/** Single-line text as a transparent PNG; long names are ellipsised to maxWidth. */
async function textPng(text, { size, color, fontfile, family, maxWidth }) {
  const label = String(text || '');
  const canvasW = Math.max(maxWidth, Math.ceil([...label].length * size) + 24);
  const canvasH = Math.ceil(size * 1.8);
  const svg = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${canvasW}" height="${canvasH}">
      <defs><style>
        ${fontFaceCss(family, fontfile)}
        .t{font-family:'${family}',sans-serif;font-size:${size}px;font-weight:700;fill:${color};}
      </style></defs>
      <text x="0" y="${size}" class="t">${escapeMarkup(label)}</text>
    </svg>`,
  );
  let data;
  let info;
  try {
    ({ data, info } = await sharp(svg).trim({ threshold: 1 }).png().toBuffer({ resolveWithObject: true }));
  } catch (_) {
    ({ data, info } = await sharp(svg).png().toBuffer({ resolveWithObject: true }));
  }
  if (info.width <= maxWidth) return { data, width: info.width, height: info.height };
  const cropped = await sharp(data)
    .extract({ left: 0, top: 0, width: maxWidth, height: info.height })
    .png()
    .toBuffer();
  return { data: cropped, width: maxWidth, height: info.height };
}

async function circle(buffer, size) {
  const mask = Buffer.from(
    `<svg width="${size}" height="${size}"><circle cx="${size / 2}" cy="${size / 2}" r="${size / 2}" fill="#fff"/></svg>`,
  );
  return sharp(buffer)
    .resize(size, size, { fit: 'cover' })
    .composite([{ input: mask, blend: 'dest-in' }])
    .png()
    .toBuffer();
}

async function initialsAvatar(name, size) {
  const letter = escapeMarkup((String(name || 'V').trim()[0] || 'V').toUpperCase());
  const svg = Buffer.from(
    `<svg width="${size}" height="${size}">
      <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="${ORANGE}"/><stop offset="1" stop-color="${ORANGE_DEEP}"/>
      </linearGradient></defs>
      <circle cx="${size / 2}" cy="${size / 2}" r="${size / 2}" fill="url(#g)"/>
    </svg>`,
  );
  const base = await sharp(svg).png().toBuffer();
  const t = await textPng(letter, {
    size: Math.round(size * 0.46),
    color: '#FFFFFF',
    fontfile: FONT_BLACK,
    family: 'Roboto Black',
    maxWidth: size,
  });
  return sharp(base)
    .composite([
      {
        input: t.data,
        left: Math.round((size - t.width) / 2),
        top: Math.round((size - t.height) / 2),
      },
    ])
    .png()
    .toBuffer();
}

/** Shadowed text so the watermark stays readable on bright and dark frames. */
async function shadowed(t) {
  const pad = 6;
  const w = t.width + pad * 2;
  const h = t.height + pad * 2;
  const shadow = await sharp(t.data)
    .extend({ top: pad, bottom: pad, left: pad, right: pad, background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .linear([0, 0, 0, 0.75], [0, 0, 0, 0])
    .blur(3)
    .png()
    .toBuffer();
  const data = await sharp({
    create: { width: w, height: h, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
  })
    .composite([
      { input: shadow, left: 1, top: 2 },
      { input: t.data, left: pad, top: pad },
    ])
    .png()
    .toBuffer();
  return { data, width: w, height: h, pad };
}

async function buildWatermark(ownerName) {
  const logoSize = 64;
  const logo = await circle(await sharp(LOGO).toBuffer(), logoSize);
  const brand = await shadowed(
    await textPng('Vero360', {
      size: 28,
      color: '#FFFFFF',
      fontfile: FONT_BOLD,
      family: 'Roboto Bold',
      maxWidth: 360,
    }),
  );
  const handle = await shadowed(
    await textPng(handleFor(ownerName), {
      size: 21,
      color: '#FFFFFF',
      fontfile: FONT_MEDIUM,
      family: 'Roboto Medium',
      maxWidth: 360,
    }),
  );
  const gap = 10;
  const textW = Math.max(brand.width, handle.width);
  const width = logoSize + gap + textW;
  const height = Math.max(logoSize, brand.height + handle.height - 10);
  const textTop = Math.round((height - (brand.height + handle.height - 10)) / 2);
  return sharp({
    create: { width, height, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
  })
    .composite([
      { input: logo, left: 0, top: Math.round((height - logoSize) / 2) },
      { input: brand.data, left: logoSize + gap - brand.pad, top: textTop - 2 },
      { input: handle.data, left: logoSize + gap - handle.pad, top: textTop + brand.height - 12 },
    ])
    .png()
    .toBuffer();
}

async function buildEndCard({ ownerName, ownerPhoto, isMerchant }) {
  const layers = [];
  const center = (w) => Math.round((W - w) / 2);

  // Soft orange glow behind the avatar keeps the card light but on-brand.
  const bg = Buffer.from(
    `<svg width="${W}" height="${H}">
      <defs>
        <radialGradient id="glow" cx="50%" cy="40%" r="55%">
          <stop offset="0" stop-color="${ORANGE}" stop-opacity="0.28"/>
          <stop offset="1" stop-color="${ORANGE}" stop-opacity="0"/>
        </radialGradient>
        <linearGradient id="bar" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stop-color="${ORANGE}"/><stop offset="1" stop-color="${ORANGE_DEEP}"/>
        </linearGradient>
      </defs>
      <rect width="${W}" height="${H}" fill="${BG}"/>
      <rect width="${W}" height="${H}" fill="url(#glow)"/>
      <rect x="0" y="${H - 10}" width="${W}" height="10" fill="url(#bar)"/>
    </svg>`,
  );

  const logoSize = 132;
  const logo = await circle(await sharp(LOGO).toBuffer(), logoSize);
  layers.push({ input: logo, left: center(logoSize), top: 150 });

  const avatarSize = 230;
  const ring = 10;
  let avatar;
  if (ownerPhoto) {
    try {
      avatar = await circle(ownerPhoto, avatarSize);
    } catch (_) {
      avatar = null;
    }
  }
  if (!avatar) avatar = await initialsAvatar(ownerName, avatarSize);
  const ringSize = avatarSize + ring * 2;
  const ringSvg = Buffer.from(
    `<svg width="${ringSize + 24}" height="${ringSize + 24}">
      <defs><linearGradient id="r" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="${ORANGE}"/><stop offset="1" stop-color="${ORANGE_DEEP}"/>
      </linearGradient>
      <filter id="s" x="-20%" y="-20%" width="140%" height="140%">
        <feDropShadow dx="0" dy="8" stdDeviation="8" flood-color="#E86A00" flood-opacity="0.35"/>
      </filter></defs>
      <circle cx="${(ringSize + 24) / 2}" cy="${(ringSize + 24) / 2}" r="${ringSize / 2}" fill="url(#r)" filter="url(#s)"/>
      <circle cx="${(ringSize + 24) / 2}" cy="${(ringSize + 24) / 2}" r="${avatarSize / 2 + 3}" fill="#fff"/>
    </svg>`,
  );
  const avatarTop = 360;
  layers.push({ input: await sharp(ringSvg).png().toBuffer(), left: center(ringSize + 24), top: avatarTop - 12 });
  layers.push({ input: avatar, left: center(avatarSize), top: avatarTop + ring });

  let y = avatarTop + ringSize + 40;
  const name = await textPng(ownerName || 'Vero360 member', {
    size: 46,
    color: INK,
    fontfile: FONT_BOLD,
    family: 'Roboto Bold',
    maxWidth: W - 80,
  });
  layers.push({ input: name.data, left: center(name.width), top: y });
  y += name.height + 10;

  const handle = await textPng(handleFor(ownerName), {
    size: 28,
    color: ORANGE_DEEP,
    fontfile: FONT_MEDIUM,
    family: 'Roboto Medium',
    maxWidth: W - 80,
  });
  layers.push({ input: handle.data, left: center(handle.width), top: y });
  y += handle.height + 26;

  const badgeText = await textPng(isMerchant ? 'Vero360 Shop' : 'Vero360 Creator', {
    size: 22,
    color: ORANGE_DEEP,
    fontfile: FONT_BOLD,
    family: 'Roboto Bold',
    maxWidth: 400,
  });
  const badgeW = badgeText.width + 44;
  const badgeH = badgeText.height + 18;
  const badge = Buffer.from(
    `<svg width="${badgeW}" height="${badgeH}">
      <rect width="${badgeW}" height="${badgeH}" rx="${badgeH / 2}" fill="${ORANGE}" fill-opacity="0.14"
        stroke="${ORANGE}" stroke-opacity="0.5" stroke-width="2"/>
    </svg>`,
  );
  layers.push({ input: await sharp(badge).png().toBuffer(), left: center(badgeW), top: y });
  layers.push({ input: badgeText.data, left: center(badgeText.width), top: y + 9 });
  y += badgeH + 56;

  const cta = await textPng(isMerchant ? 'Shop with me on Vero360' : 'Follow me on Vero360', {
    size: 30,
    color: '#FFFFFF',
    fontfile: FONT_BOLD,
    family: 'Roboto Bold',
    maxWidth: W - 160,
  });
  const ctaW = Math.min(W - 100, cta.width + 96);
  const ctaH = 86;
  const ctaBg = Buffer.from(
    `<svg width="${ctaW + 30}" height="${ctaH + 30}">
      <defs><linearGradient id="c" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" stop-color="${ORANGE}"/><stop offset="1" stop-color="${ORANGE_DEEP}"/>
      </linearGradient>
      <filter id="s" x="-20%" y="-40%" width="140%" height="180%">
        <feDropShadow dx="0" dy="8" stdDeviation="7" flood-color="#E86A00" flood-opacity="0.35"/>
      </filter></defs>
      <rect x="15" y="10" width="${ctaW}" height="${ctaH}" rx="${ctaH / 2}" fill="url(#c)" filter="url(#s)"/>
    </svg>`,
  );
  layers.push({ input: await sharp(ctaBg).png().toBuffer(), left: center(ctaW + 30), top: y - 10 });
  layers.push({ input: cta.data, left: center(cta.width), top: y + Math.round((ctaH - cta.height) / 2) });

  const foot = await textPng('Download Vero360 · One App. Everything.', {
    size: 23,
    color: MUTED,
    fontfile: FONT_MEDIUM,
    family: 'Roboto Medium',
    maxWidth: W - 60,
  });
  layers.push({ input: foot.data, left: center(foot.width), top: H - 120 });

  return sharp(bg).composite(layers).png().toBuffer();
}

function run(args) {
  return new Promise((resolve, reject) => {
    execFile(ffmpegBin(), args, { maxBuffer: 32 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) {
        err.stderr = String(stderr || '').slice(-4000);
        reject(err);
      } else {
        resolve(String(stderr || ''));
      }
    });
  });
}

/** Duration and whether there's an audio track, from ffmpeg's banner (no ffprobe in ffmpeg-static). */
async function probe(input) {
  let out = '';
  try {
    await run(['-hide_banner', '-i', input]);
  } catch (e) {
    out = e.stderr || '';
  }
  const m = out.match(/Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)/);
  const duration = m ? Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]) : 0;
  return { duration, hasAudio: /Stream #.*Audio:/.test(out) };
}

/**
 * Re-encodes a reel at 720x1280 with a moving Vero360 watermark and a
 * 3-second end card showing the owner, like TikTok/Instagram downloads.
 */
async function renderBrandedReel({ inputPath, outputPath, workDir, ownerName, ownerPhoto, isMerchant }) {
  const { duration, hasAudio } = await probe(inputPath);
  if (!duration) throw new Error('Could not read the video.');
  const half = (duration / 2).toFixed(3);
  const slide = 0.8;
  // Starts top-left, glides (smoothstep) to the top-right halfway through.
  const p = `min(max((t-${half})/${slide},0),1)`;
  const markX = `28+(W-w-56)*(${p})*(${p})*(3-2*(${p}))`;

  const markPath = path.join(workDir, 'watermark.png');
  const endPath = path.join(workDir, 'endcard.png');
  await sharp(await buildWatermark(ownerName)).toFile(markPath);
  await sharp(await buildEndCard({ ownerName, ownerPhoto, isMerchant })).toFile(endPath);

  const args = [
    '-hide_banner', '-y',
    '-i', inputPath,
    '-i', markPath,
    '-loop', '1', '-framerate', '30', '-t', String(END_SECONDS), '-i', endPath,
    '-f', 'lavfi', '-t', String(END_SECONDS), '-i', 'anullsrc=r=44100:cl=stereo',
  ];
  if (!hasAudio) {
    args.push('-f', 'lavfi', '-t', duration.toFixed(3), '-i', 'anullsrc=r=44100:cl=stereo');
  }
  const mainAudio = hasAudio
    ? `[0:a]aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo,apad,atrim=duration=${duration.toFixed(3)},asetpts=PTS-STARTPTS[a0];`
    : `[4:a]aformat=sample_fmts=fltp:channel_layouts=stereo[a0];`;
  const filter =
    `[0:v]scale=${W}:${H}:force_original_aspect_ratio=decrease,` +
    `pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,fps=30,format=yuv420p[base];` +
    `[base][1:v]overlay=x='${markX}':y=110:eval=frame,format=yuv420p[main];` +
    `[2:v]scale=${W}:${H},setsar=1,fps=30,format=yuv420p,fade=t=in:st=0:d=0.4:color=white[end];` +
    mainAudio +
    `[3:a]aformat=sample_fmts=fltp:channel_layouts=stereo[a1];` +
    `[main][a0][end][a1]concat=n=2:v=1:a=1[v][a]`;
  args.push(
    '-filter_complex', filter,
    '-map', '[v]', '-map', '[a]',
    '-c:v', 'libx264', '-preset', 'superfast', '-crf', '24',
    '-pix_fmt', 'yuv420p', '-threads', '0',
    '-c:a', 'aac', '-b:a', '128k',
    '-movflags', '+faststart',
    outputPath,
  );
  await run(args);
}

module.exports = { renderBrandedReel, buildWatermark, buildEndCard, handleFor };

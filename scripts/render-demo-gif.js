"use strict";

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const ASSET_DIR = path.join(ROOT, "docs", "assets");
const FRAME_DIR = path.join(ROOT, ".swipesheet", "demo-frames");
const SAMPLE_IMAGES = [
  path.join(ROOT, "examples", "images", "generated-scenic.png"),
  path.join(ROOT, "examples", "images", "generated-persona.png"),
  path.join(ROOT, "examples", "images", "generated-still-life.png"),
];

const frames = [
  {
    active: 0,
    status: "use",
    statusLabel: "Use this",
    meta: "generated-scenic.png",
    note: "Strong portfolio landscape. Use as a hero or gallery candidate.",
    counts: { use: 1, maybe: 0, reject: 0 },
    progress: "1 / 3 reviewed",
  },
  {
    active: 1,
    status: "maybe",
    statusLabel: "Maybe",
    meta: "generated-persona.png",
    note: "Good styling. Keep as a candidate, but check identity consistency.",
    counts: { use: 1, maybe: 1, reject: 0 },
    progress: "2 / 3 reviewed",
  },
  {
    active: 2,
    status: "reject",
    statusLabel: "Disregard",
    meta: "generated-still-life.png",
    note: "Too busy for this pass. Do not wire into the current project.",
    counts: { use: 1, maybe: 1, reject: 1 },
    progress: "3 / 3 reviewed",
  },
  {
    active: 0,
    status: "export",
    statusLabel: "Export ready",
    meta: "Copy-ready feedback",
    note: "Selected images are grouped with full original paths and notes.",
    counts: { use: 1, maybe: 1, reject: 1 },
    progress: "3 / 3 reviewed",
    export: true,
  },
];

function esc(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function href(filePath) {
  return `file://${filePath}`;
}

function statusColor(status) {
  return {
    use: ["#207a4b", "#e4f3eb"],
    reject: ["#b23b3b", "#f8e7e5"],
    maybe: ["#8a6516", "#f6edcf"],
    export: ["#244f9f", "#e9effd"],
  }[status] || ["#636762", "#eceee8"];
}

function button(label, x, y, active, color, fill) {
  return `
    <rect x="${x}" y="${y}" width="126" height="42" rx="7" fill="${active ? fill : "#ffffff"}" stroke="${active ? color : "#d8d9d4"}" stroke-width="2"/>
    <text x="${x + 63}" y="${y + 27}" font-size="14" font-weight="700" text-anchor="middle" fill="${active ? color : "#202124"}">${esc(label)}</text>
  `;
}

function wrapText(text, maxChars = 31) {
  const words = String(text).split(/\s+/);
  const lines = [];
  let current = "";

  for (const word of words) {
    const next = current ? `${current} ${word}` : word;
    if (next.length > maxChars && current) {
      lines.push(current);
      current = word;
    } else {
      current = next;
    }
  }

  if (current) lines.push(current);
  return lines.slice(0, 4);
}

function noteLines(note, x, y) {
  return wrapText(note)
    .map((line, index) => `<text x="${x}" y="${y + index * 18}" font-size="13" fill="#202124">${esc(line)}</text>`)
    .join("\n");
}

function thumb(image, x, y, active, status) {
  const [color] = statusColor(status);
  return `
    <rect x="${x}" y="${y}" width="94" height="68" rx="7" fill="#111111" stroke="${active ? "#2d6cdf" : "transparent"}" stroke-width="3"/>
    <clipPath id="thumb-${x}-${y}"><rect x="${x + 3}" y="${y + 3}" width="88" height="62" rx="5"/></clipPath>
    <image href="${href(image)}" x="${x + 3}" y="${y + 3}" width="88" height="62" preserveAspectRatio="xMidYMid slice" clip-path="url(#thumb-${x}-${y})"/>
    <circle cx="${x + 78}" cy="${y + 53}" r="11" fill="${color}"/>
  `;
}

function renderFrame(frame) {
  const [accent, soft] = statusColor(frame.status);
  const activeImage = SAMPLE_IMAGES[frame.active];
  const exportOverlay = frame.export
    ? `
      <rect x="176" y="92" width="608" height="416" rx="12" fill="#ffffff" stroke="#d8d9d4" stroke-width="2"/>
      <text x="210" y="138" font-size="24" font-weight="800" fill="#202124">Copy export</text>
      <text x="210" y="164" font-size="14" fill="#636762">Paste this into your AI CLI or another project.</text>
      <rect x="210" y="192" width="540" height="236" rx="7" fill="#f7f7f5" stroke="#d8d9d4"/>
      <text x="232" y="228" font-size="15" font-family="Menlo, monospace" fill="#202124"># Image review export: Demo review</text>
      <text x="232" y="262" font-size="15" font-family="Menlo, monospace" fill="#202124">Use: generated-scenic.png</text>
      <text x="232" y="296" font-size="15" font-family="Menlo, monospace" fill="#202124">Maybe: generated-persona.png</text>
      <text x="232" y="330" font-size="15" font-family="Menlo, monospace" fill="#202124">Reject: generated-still-life.png</text>
      <rect x="622" y="450" width="128" height="38" rx="7" fill="#202124"/>
      <text x="686" y="474" font-size="14" font-weight="700" text-anchor="middle" fill="#ffffff">Copy text</text>
    `
    : "";

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="960" height="600" viewBox="0 0 960 600">
  <rect width="960" height="600" fill="#f7f7f5"/>
  <rect x="0" y="0" width="960" height="600" fill="#f7f7f5"/>
  <rect x="18" y="18" width="624" height="564" rx="10" fill="#f7f7f5"/>
  <rect x="660" y="0" width="300" height="600" fill="#ffffff"/>
  <line x1="660" y1="0" x2="660" y2="600" stroke="#d8d9d4"/>

  <text x="34" y="48" font-size="22" font-weight="800" fill="#202124">SwipeSheet</text>
  <text x="34" y="70" font-size="13" fill="#636762">Native macOS review for portfolio and AI content assets</text>
  <text x="624" y="61" font-size="13" text-anchor="end" fill="#636762">${esc(frame.progress)}</text>

  <rect x="34" y="92" width="592" height="360" rx="9" fill="#111111"/>
  <clipPath id="active-image"><rect x="34" y="92" width="592" height="360" rx="9"/></clipPath>
  <image href="${href(activeImage)}" x="34" y="92" width="592" height="360" preserveAspectRatio="xMidYMid meet" clip-path="url(#active-image)"/>
  ${exportOverlay}

  <g>
    ${thumb(SAMPLE_IMAGES[0], 34, 478, frame.active === 0, frame.active === 0 ? frame.status : "use")}
    ${thumb(SAMPLE_IMAGES[1], 138, 478, frame.active === 1, frame.active === 1 ? frame.status : "maybe")}
    ${thumb(SAMPLE_IMAGES[2], 242, 478, frame.active === 2, frame.active === 2 ? frame.status : "reject")}
  </g>

  <text x="686" y="40" font-size="13" fill="#636762">Image ${frame.active + 1} of 3</text>
  <rect x="790" y="22" width="132" height="28" rx="14" fill="${soft}" stroke="${accent}"/>
  <text x="856" y="41" font-size="13" font-weight="700" text-anchor="middle" fill="${accent}">${esc(frame.statusLabel)}</text>

  <text x="686" y="88" font-size="17" font-weight="800" fill="#202124">${esc(frame.meta)}</text>
  <text x="686" y="112" font-size="12" fill="#636762">/examples/images/${esc(frame.meta)}</text>

  <g>
    ${button("X Disregard", 686, 150, frame.status === "reject", "#b23b3b", "#f8e7e5")}
    ${button("Y Use this", 820, 150, frame.status === "use", "#207a4b", "#e4f3eb")}
    ${button("M Maybe", 686, 202, frame.status === "maybe", "#8a6516", "#f6edcf")}
    ${button("N Notes", 820, 202, false, "#244f9f", "#e9effd")}
  </g>

  <text x="686" y="278" font-size="13" font-weight="800" fill="#202124">Feedback for this image</text>
  <rect x="686" y="294" width="236" height="104" rx="7" fill="#ffffff" stroke="#d8d9d4"/>
  ${noteLines(frame.note, 700, 320)}

  <g>
    <rect x="686" y="430" width="70" height="58" rx="7" fill="#fbfbfa" stroke="#d8d9d4"/>
    <text x="721" y="454" font-size="22" font-weight="800" text-anchor="middle" fill="#202124">${frame.counts.use}</text>
    <text x="721" y="474" font-size="12" text-anchor="middle" fill="#636762">Use</text>
    <rect x="769" y="430" width="70" height="58" rx="7" fill="#fbfbfa" stroke="#d8d9d4"/>
    <text x="804" y="454" font-size="22" font-weight="800" text-anchor="middle" fill="#202124">${frame.counts.maybe}</text>
    <text x="804" y="474" font-size="12" text-anchor="middle" fill="#636762">Maybe</text>
    <rect x="852" y="430" width="70" height="58" rx="7" fill="#fbfbfa" stroke="#d8d9d4"/>
    <text x="887" y="454" font-size="22" font-weight="800" text-anchor="middle" fill="#202124">${frame.counts.reject}</text>
    <text x="887" y="474" font-size="12" text-anchor="middle" fill="#636762">Reject</text>
  </g>

  <rect x="686" y="528" width="236" height="42" rx="7" fill="#202124"/>
  <text x="804" y="555" font-size="14" font-weight="800" text-anchor="middle" fill="#ffffff">Finish and export</text>
</svg>`;
}

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8", stdio: "pipe" });
  if (result.status !== 0) {
    const output = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
    throw new Error(`${command} ${args.join(" ")} failed\n${output}`);
  }
}

function main() {
  fs.mkdirSync(ASSET_DIR, { recursive: true });
  fs.mkdirSync(FRAME_DIR, { recursive: true });

  const framePngs = frames.map((frame, index) => {
    const svgPath = path.join(FRAME_DIR, `frame-${String(index + 1).padStart(2, "0")}.svg`);
    const pngPath = path.join(FRAME_DIR, `frame-${String(index + 1).padStart(2, "0")}.png`);
    fs.writeFileSync(svgPath, renderFrame(frame));
    run("magick", [svgPath, pngPath]);
    return pngPath;
  });

  const posterPath = path.join(ASSET_DIR, "demo-poster.png");
  const gifPath = path.join(ASSET_DIR, "demo.gif");
  fs.copyFileSync(framePngs[0], posterPath);
  run("magick", ["-delay", "115", "-loop", "0", ...framePngs, "-layers", "Optimize", gifPath]);

  console.log(`wrote ${posterPath}`);
  console.log(`wrote ${gifPath}`);
}

main();

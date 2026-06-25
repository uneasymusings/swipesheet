"use strict";

const fs = require("fs");
const path = require("path");
const {
  IMAGE_EXTENSIONS,
  MANIFEST_EXTENSIONS,
  hashString,
  normalizePath,
  toPosixPath,
} = require("./path-utils");

function isImagePath(filePath, extensions = IMAGE_EXTENSIONS) {
  return extensions.has(path.extname(filePath).toLowerCase());
}

function isManifestPath(filePath) {
  return MANIFEST_EXTENSIONS.has(path.extname(filePath).toLowerCase());
}

function tryRealPath(filePath) {
  try {
    return fs.realpathSync.native(filePath);
  } catch (_error) {
    return path.resolve(filePath);
  }
}

function walkImages(dirPath, options = {}) {
  const extensions = options.extensions || IMAGE_EXTENSIONS;
  const includeHidden = Boolean(options.includeHidden);
  const found = [];

  function visit(current) {
    const entries = fs.readdirSync(current, { withFileTypes: true }).sort((a, b) =>
      a.name.localeCompare(b.name, undefined, { numeric: true })
    );

    for (const entry of entries) {
      if (!includeHidden && entry.name.startsWith(".")) continue;
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        visit(fullPath);
      } else if (entry.isFile() && isImagePath(fullPath, extensions)) {
        found.push({ path: fullPath });
      }
    }
  }

  visit(dirPath);
  return found;
}

function valueLooksLikePath(value) {
  if (typeof value !== "string") return false;
  const trimmed = value.trim();
  if (!trimmed) return false;
  return trimmed.startsWith("/") || trimmed.startsWith("~/") || trimmed.includes(path.sep) || isImagePath(trimmed);
}

function normalizeManifestItem(rawItem, baseDir) {
  if (typeof rawItem === "string") {
    return { path: normalizePath(rawItem, baseDir) };
  }

  if (!rawItem || typeof rawItem !== "object") return null;

  const pathValue =
    rawItem.path ||
    rawItem.filePath ||
    rawItem.fullPath ||
    rawItem.originalPath ||
    rawItem.original ||
    rawItem.src ||
    rawItem.url;

  if (!valueLooksLikePath(pathValue)) return null;

  const normalized = {
    path: normalizePath(pathValue, baseDir),
    label: rawItem.label || rawItem.folder || rawItem.roll || rawItem.group || rawItem.persona || undefined,
    note: rawItem.note || rawItem.notes || rawItem.feedback || undefined,
    metadata: {},
  };

  for (const [key, value] of Object.entries(rawItem)) {
    if (!["path", "filePath", "fullPath", "originalPath", "original", "src", "url", "note", "notes"].includes(key)) {
      normalized.metadata[key] = value;
    }
  }

  return normalized;
}

function parseDelimitedManifest(filePath) {
  const baseDir = path.dirname(filePath);
  const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);
  const items = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const columns = trimmed.split(/\t|,/).map((value) => value.trim()).filter(Boolean);
    const pathColumn = columns.find(valueLooksLikePath);
    if (!pathColumn) continue;

    items.push({
      path: normalizePath(pathColumn, baseDir),
      label: columns.length > 1 ? columns.find((value) => value !== pathColumn) : undefined,
    });
  }

  return items;
}

function parseJsonManifest(filePath) {
  const baseDir = path.dirname(filePath);
  const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
  const rawItems = Array.isArray(parsed)
    ? parsed
    : parsed.images || parsed.items || parsed.files || parsed.picks || parsed.results || [];

  if (!Array.isArray(rawItems)) {
    throw new Error(`JSON manifest must be an array or contain images/items/files/picks/results: ${filePath}`);
  }

  return rawItems.map((item) => normalizeManifestItem(item, baseDir)).filter(Boolean);
}

function parseManifest(filePath) {
  if (path.extname(filePath).toLowerCase() === ".json") {
    return parseJsonManifest(filePath);
  }
  return parseDelimitedManifest(filePath);
}

function itemLabel(filePath, rootDir, providedLabel) {
  if (providedLabel) return String(providedLabel);
  const parent = path.basename(path.dirname(filePath));
  if (parent && parent !== path.basename(rootDir)) return parent;
  return path.basename(rootDir);
}

function discoverImages(sources, options = {}) {
  const rootDir = options.rootDir || process.cwd();
  const limit = Number.isFinite(options.limit) && options.limit > 0 ? options.limit : Infinity;
  const discovered = [];

  for (const source of sources) {
    const sourcePath = normalizePath(source, rootDir);
    if (!fs.existsSync(sourcePath)) {
      throw new Error(`Source does not exist: ${sourcePath}`);
    }

    const stat = fs.statSync(sourcePath);
    if (stat.isDirectory()) {
      discovered.push(...walkImages(sourcePath, options));
    } else if (stat.isFile() && isImagePath(sourcePath, options.extensions || IMAGE_EXTENSIONS)) {
      discovered.push({ path: sourcePath });
    } else if (stat.isFile() && isManifestPath(sourcePath)) {
      discovered.push(...parseManifest(sourcePath));
    } else {
      throw new Error(`Unsupported source. Expected an image, directory, or manifest: ${sourcePath}`);
    }

    if (discovered.length >= limit) break;
  }

  const seen = new Set();
  const items = [];

  for (const rawItem of discovered) {
    if (items.length >= limit) break;
    const absolutePath = normalizePath(rawItem.path, rootDir);
    if (!fs.existsSync(absolutePath)) continue;
    const stat = fs.statSync(absolutePath);
    if (!stat.isFile() || !isImagePath(absolutePath, options.extensions || IMAGE_EXTENSIONS)) continue;

    const realPath = tryRealPath(absolutePath);
    if (seen.has(realPath)) continue;
    seen.add(realPath);

    const index = items.length + 1;
    const extension = path.extname(absolutePath).toLowerCase();
    const relativePath = path.relative(rootDir, absolutePath);
    const id = `img_${String(index).padStart(5, "0")}_${hashString(realPath)}`;

    items.push({
      id,
      index,
      path: absolutePath,
      realPath,
      filename: path.basename(absolutePath),
      extension,
      label: itemLabel(absolutePath, rootDir, rawItem.label),
      relativePath: toPosixPath(relativePath.startsWith("..") ? absolutePath : relativePath),
      note: rawItem.note || "",
      metadata: rawItem.metadata || {},
    });
  }

  return items;
}

module.exports = {
  discoverImages,
  isImagePath,
  parseManifest,
  walkImages,
};

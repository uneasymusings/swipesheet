"use strict";

const crypto = require("crypto");
const os = require("os");
const path = require("path");

const IMAGE_EXTENSIONS = new Set([
  ".jpg",
  ".jpeg",
  ".png",
  ".gif",
  ".webp",
  ".bmp",
  ".svg",
  ".avif",
  ".heic",
  ".heif",
  ".tif",
  ".tiff",
  ".dng",
  ".cr2",
  ".nef",
  ".arw",
  ".raf",
  ".rw2",
]);

const BROWSER_IMAGE_EXTENSIONS = new Set([
  ".jpg",
  ".jpeg",
  ".png",
  ".gif",
  ".webp",
  ".bmp",
  ".svg",
  ".avif",
]);

const MANIFEST_EXTENSIONS = new Set([".json", ".txt", ".list", ".csv", ".tsv"]);

function expandHome(input) {
  if (!input || input === "~") return os.homedir();
  if (input.startsWith("~/")) return path.join(os.homedir(), input.slice(2));
  return input;
}

function normalizePath(input, baseDir = process.cwd()) {
  const expanded = expandHome(String(input));
  return path.isAbsolute(expanded) ? path.normalize(expanded) : path.resolve(baseDir, expanded);
}

function hashString(value, length = 12) {
  return crypto.createHash("sha1").update(String(value)).digest("hex").slice(0, length);
}

function slugify(value, fallback = "session") {
  const slug = String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return slug || fallback;
}

function toPosixPath(value) {
  return String(value).split(path.sep).join("/");
}

module.exports = {
  BROWSER_IMAGE_EXTENSIONS,
  IMAGE_EXTENSIONS,
  MANIFEST_EXTENSIONS,
  expandHome,
  hashString,
  normalizePath,
  slugify,
  toPosixPath,
};

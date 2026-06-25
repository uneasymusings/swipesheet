"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { discoverImages, parseManifest } = require("../src/lib/images");

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "swipesheet-test-"));
}

function touch(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, "placeholder");
}

test("discovers supported images recursively in stable order", () => {
  const root = tempDir();
  touch(path.join(root, "b", "002.png"));
  touch(path.join(root, "a", "001.jpg"));
  touch(path.join(root, "a", "notes.md"));
  touch(path.join(root, ".hidden", "003.jpg"));

  const items = discoverImages([root], { rootDir: root });

  assert.equal(items.length, 2);
  assert.deepEqual(items.map((item) => item.relativePath), ["a/001.jpg", "b/002.png"]);
  assert.equal(items[0].index, 1);
  assert.equal(items[0].label, "a");
});

test("parses JSON manifests with relative paths and metadata", () => {
  const root = tempDir();
  touch(path.join(root, "images", "candidate.jpg"));
  const manifest = path.join(root, "manifest.json");
  fs.writeFileSync(
    manifest,
    JSON.stringify({
      images: [
        {
          path: "images/candidate.jpg",
          label: "Mari",
          score: 8,
          note: "Good pose",
        },
      ],
    })
  );

  const parsed = parseManifest(manifest);

  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].path, path.join(root, "images", "candidate.jpg"));
  assert.equal(parsed[0].label, "Mari");
  assert.equal(parsed[0].note, "Good pose");
  assert.equal(parsed[0].metadata.score, 8);
});

test("dedupes the same file when discovered from multiple sources", () => {
  const root = tempDir();
  const file = path.join(root, "same.jpg");
  touch(file);

  const items = discoverImages([root, file], { rootDir: root });

  assert.equal(items.length, 1);
  assert.equal(items[0].path, file);
});

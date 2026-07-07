"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { buildContentSetsManifest, buildPersonaManifest } = require("../src/lib/autogen");

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "swipesheet-autogen-test-"));
}

function touch(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, "placeholder");
}

test("persona manifests include canonical labels and note requirements", () => {
  const root = tempDir();
  touch(path.join(root, "references", "mari", "candidate-01.png"));
  touch(path.join(root, "references", "mari", "candidate-02.png"));

  const manifest = buildPersonaManifest(path.join(root, "references"), { rootDir: root });
  const group = manifest.groups[0];

  assert.equal(manifest.reviewType, "single_select_per_group");
  assert.deepEqual(manifest.itemActions, ["use", "maybe", "reject"]);
  assert.equal(group.constraints.minSelected, 1);
  assert.equal(group.constraints.maxSelected, 1);
  assert.equal(group.metadata.itemActionLabels.use, "Canonical");
  assert.equal(group.metadata.groupActionLabels.approve, "Confirm mari canonical");
  assert.deepEqual(group.metadata.noteRequiredStatuses, ["request_changes"]);
});

test("content-set manifests include publish review labels and note requirements", () => {
  const root = tempDir();
  touch(path.join(root, "out", "slide-01.png"));
  touch(path.join(root, "out", "slide-02.png"));
  const memoryFile = path.join(root, "pipeline-memory.json");
  fs.writeFileSync(
    memoryFile,
    JSON.stringify({
      contentSets: [
        {
          contentSetId: "cs_123",
          hook: "Best EDC pocket tool",
          caption: "Caption text",
          platform: "tiktok",
          slides: [
            { path: "out/slide-01.png", role: "hook" },
            { path: "out/slide-02.png", role: "cta" },
          ],
        },
      ],
    })
  );

  const manifest = buildContentSetsManifest(memoryFile, { rootDir: root });
  const group = manifest.groups[0];

  assert.equal(manifest.reviewType, "storyboard");
  assert.deepEqual(manifest.itemActions, ["use", "replace", "reject"]);
  assert.equal(group.metadata.itemActionLabels.replace, "Replace slide");
  assert.equal(group.metadata.groupActionLabels.approve_sequence, "Approve sequence");
  assert.deepEqual(group.metadata.noteRequiredStatuses, ["needs_reorder", "request_changes"]);
  assert.equal(group.metadata.hook, "Best EDC pocket tool");
  assert.equal(group.constraints.requiresOrder, true);
});

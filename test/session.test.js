"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { createSession, latestSessionPath, loadSession, resolveSessionFile, setDecision } = require("../src/lib/session");

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "swipesheet-session-test-"));
}

function writeSession(filePath, overrides = {}) {
  const session = {
    version: 1,
    id: "test-session",
    title: "Test session",
    rootDir: path.dirname(filePath),
    items: [
      {
        id: "img_1",
        index: 1,
        path: "/tmp/img-1.png",
        filename: "img-1.png",
        label: "Image 1",
        metadata: {},
      },
    ],
    groups: [],
    decisions: {
      img_1: { status: "unreviewed", note: "", reviewedAt: null },
    },
    ...overrides,
  };
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(session, null, 2)}\n`);
  return session;
}

test("creates grouped sessions with a latest pointer", () => {
  const root = tempDir();
  const imagePath = path.join(root, "slide.png");
  fs.writeFileSync(imagePath, "placeholder");

  const { session, sessionFile } = createSession({
    rootDir: root,
    title: "Autogen review",
    kind: "autogen_review",
    reviewType: "storyboard",
    itemActions: ["use", "replace", "reject"],
    groupActions: ["approve_sequence", "request_changes"],
    items: [
      {
        id: "slide_1",
        index: 1,
        path: imagePath,
        filename: "slide.png",
        label: "Hook",
        metadata: {},
      },
    ],
    groups: [
      {
        id: "cs_123",
        index: 1,
        label: "Content set",
        reviewType: "storyboard",
        metadata: { contentSetId: "cs_123" },
        constraints: { requiresOrder: true },
        itemIds: ["slide_1"],
      },
    ],
  });

  const latestPath = latestSessionPath(root);
  const latest = loadSession(latestPath);

  assert.equal(fs.existsSync(sessionFile), true);
  assert.equal(fs.existsSync(latestPath), true);
  assert.equal(session.kind, "autogen_review");
  assert.deepEqual(session.groupActions, ["approve_sequence", "request_changes", "skipped"]);
  assert.equal(latest.session.id, session.id);
  assert.equal(latest.sessionFile, fs.realpathSync.native(sessionFile));
  assert.equal(latest.session.groups[0].id, "cs_123");
  assert.deepEqual(latest.session.groupDecisions.cs_123.itemOrder, ["slide_1"]);
});

test("resolves a copied latest.json to the newest timestamped session", () => {
  const root = tempDir();
  const sessionDir = path.join(root, ".swipesheet", "sessions");
  const oldFile = path.join(sessionDir, "20260101T000000Z-old.json");
  const newFile = path.join(sessionDir, "20260102T000000Z-new.json");
  const latestFile = path.join(sessionDir, "latest.json");

  writeSession(oldFile, { id: "old-session" });
  writeSession(newFile, { id: "new-session" });
  writeSession(latestFile, { id: "copied-latest" });
  fs.utimesSync(oldFile, new Date("2026-01-01T00:00:00Z"), new Date("2026-01-01T00:00:00Z"));
  fs.utimesSync(newFile, new Date("2026-01-02T00:00:00Z"), new Date("2026-01-02T00:00:00Z"));
  fs.utimesSync(latestFile, new Date("2026-01-03T00:00:00Z"), new Date("2026-01-03T00:00:00Z"));

  assert.equal(resolveSessionFile(latestFile), newFile);
  assert.equal(loadSession(latestFile).session.id, "new-session");
});

test("rejects unsupported future session versions", () => {
  const root = tempDir();
  const sessionFile = path.join(root, ".swipesheet", "sessions", "future.json");
  writeSession(sessionFile, { version: 2 });

  assert.throws(() => loadSession(sessionFile), /Unsupported session version 2/);
});

test("rejects duplicate item and group ids", () => {
  const root = tempDir();
  const sessionFile = path.join(root, ".swipesheet", "sessions", "duplicates.json");
  writeSession(sessionFile, {
    items: [
      { id: "dup", index: 1, path: "/tmp/a.png", filename: "a.png", label: "A", metadata: {} },
      { id: "dup", index: 2, path: "/tmp/b.png", filename: "b.png", label: "B", metadata: {} },
    ],
    groups: [
      { id: "group_dup", index: 1, label: "Group A", itemIds: ["dup"], metadata: {}, constraints: {} },
      { id: "group_dup", index: 2, label: "Group B", itemIds: ["dup"], metadata: {}, constraints: {} },
    ],
    decisions: {
      dup: { status: "unreviewed", note: "", reviewedAt: null },
    },
  });

  assert.throws(() => loadSession(sessionFile), /Duplicate item id: dup/);
});

test("rejects duplicate group ids", () => {
  const root = tempDir();
  const sessionFile = path.join(root, ".swipesheet", "sessions", "duplicate-groups.json");
  writeSession(sessionFile, {
    groups: [
      { id: "group_dup", index: 1, label: "Group A", itemIds: ["img_1"], metadata: {}, constraints: {} },
      { id: "group_dup", index: 2, label: "Group B", itemIds: ["img_1"], metadata: {}, constraints: {} },
    ],
    groupDecisions: {
      group_dup: { status: "unreviewed", note: "", reviewedAt: null, itemOrder: ["img_1"] },
    },
  });

  assert.throws(() => loadSession(sessionFile), /Duplicate group id: group_dup/);
});

test("rejects duplicate ids while creating sessions", () => {
  const root = tempDir();

  assert.throws(
    () =>
      createSession({
        rootDir: root,
        title: "Duplicates",
        items: [
          { id: "img", path: "/tmp/a.png" },
          { id: "img", path: "/tmp/b.png" },
        ],
      }),
    /Duplicate item id: img/
  );
});

test("accepts manifest-defined item actions in session decisions", () => {
  const session = {
    items: [{ id: "slide_1" }],
    itemActions: ["use", "replace", "reject"],
    decisions: {
      slide_1: { status: "unreviewed", note: "", reviewedAt: null },
    },
  };

  const decision = setDecision(session, { id: "slide_1", status: "replace", note: "Swap CTA" });

  assert.equal(decision.status, "replace");
  assert.equal(decision.note, "Swap CTA");
});

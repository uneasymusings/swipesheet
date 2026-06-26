"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { createSession, latestSessionPath, loadSession, setDecision } = require("../src/lib/session");

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "swipesheet-session-test-"));
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
  assert.equal(latest.session.id, session.id);
  assert.equal(latest.session.groups[0].id, "cs_123");
  assert.deepEqual(latest.session.groupDecisions.cs_123.itemOrder, ["slide_1"]);
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

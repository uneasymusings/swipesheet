"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { buildExport } = require("../src/lib/exporter");

test("builds copy-ready agent export grouped by decisions", () => {
  const session = {
    id: "session-1",
    title: "Persona candidates",
    prompt: "Pick one canonical identity reference.",
    items: [
      {
        id: "a",
        index: 1,
        label: "Mari",
        filename: "mari-01.jpg",
        path: "/tmp/mari-01.jpg",
        metadata: {},
      },
      {
        id: "b",
        index: 2,
        label: "Mari",
        filename: "mari-02.jpg",
        path: "/tmp/mari-02.jpg",
        metadata: {},
      },
    ],
    decisions: {
      a: { status: "use", note: "Canonical", reviewedAt: "now" },
      b: { status: "reject", note: "Face drift", reviewedAt: "now" },
    },
  };

  const text = buildExport(session);

  assert.match(text, /# Image review export: Persona candidates/);
  assert.match(text, /Selected images:/);
  assert.match(text, /#0001 \| Mari \| mari-01\.jpg/);
  assert.match(text, /note: Canonical/);
  assert.match(text, /Rejected images with notes:/);
  assert.match(text, /Face drift/);
});

test("builds machine-readable JSON export", () => {
  const session = {
    id: "session-2",
    title: "Portfolio",
    items: [
      {
        id: "a",
        index: 1,
        label: "Roll",
        filename: "frame.tif",
        path: "/tmp/frame.tif",
        metadata: { score: 9 },
      },
    ],
    decisions: {
      a: { status: "maybe", note: "Crop square", reviewedAt: "now" },
    },
  };

  const parsed = JSON.parse(buildExport(session, { format: "json" }));

  assert.equal(parsed.session.title, "Portfolio");
  assert.equal(parsed.results[0].status, "maybe");
  assert.equal(parsed.results[0].metadata.score, 9);
});

test("builds autogen export with groups, order, decisions, and metadata", () => {
  const session = {
    id: "session-3",
    title: "Content set review",
    prompt: "Approve the slideshow sequence.",
    rootDir: "/tmp/project",
    kind: "autogen_review",
    reviewType: "storyboard",
    itemActions: ["use", "replace", "reject"],
    groupActions: ["approve_sequence", "needs_reorder", "request_changes"],
    metadata: { source: "pipeline-memory" },
    createdAt: "created",
    updatedAt: "updated",
    finishedAt: "finished",
    groups: [
      {
        id: "cs_123",
        index: 1,
        label: "EDC verdict slideshow",
        reviewType: "storyboard",
        metadata: { contentSetId: "cs_123", platform: "tiktok", caption: "Caption" },
        constraints: { requiresOrder: true, maxSelected: 10 },
        itemIds: ["slide_1", "slide_2"],
      },
    ],
    items: [
      {
        id: "slide_1",
        index: 1,
        groupId: "cs_123",
        label: "Hook",
        filename: "slide-01.png",
        path: "/tmp/project/out/slide-01.png",
        relativePath: "out/slide-01.png",
        order: 1,
        metadata: { role: "hook" },
      },
      {
        id: "slide_2",
        index: 2,
        groupId: "cs_123",
        label: "CTA",
        filename: "slide-02.png",
        path: "/tmp/project/out/slide-02.png",
        relativePath: "out/slide-02.png",
        order: 2,
        metadata: { role: "cta" },
      },
    ],
    decisions: {
      slide_1: { status: "use", note: "Strong hook", reviewedAt: "now" },
      slide_2: { status: "replace", note: "CTA too weak", reviewedAt: "now" },
    },
    groupDecisions: {
      cs_123: {
        status: "needs_reorder",
        note: "Move CTA earlier",
        reviewedAt: "now",
        itemOrder: ["slide_2", "slide_1"],
      },
    },
  };

  const parsed = JSON.parse(buildExport(session, { format: "autogen" }));

  assert.equal(parsed.kind, "autogen_review_export");
  assert.equal(parsed.session.reviewType, "storyboard");
  assert.deepEqual(parsed.actions.item, ["use", "replace", "reject"]);
  assert.equal(parsed.groups[0].id, "cs_123");
  assert.equal(parsed.groups[0].status, "needs_reorder");
  assert.deepEqual(parsed.groups[0].itemOrder, ["slide_2", "slide_1"]);
  assert.equal(parsed.groups[0].items[0].id, "slide_2");
  assert.equal(parsed.results[1].status, "replace");
});

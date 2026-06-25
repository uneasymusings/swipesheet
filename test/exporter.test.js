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

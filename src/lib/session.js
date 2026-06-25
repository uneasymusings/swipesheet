"use strict";

const fs = require("fs");
const path = require("path");
const { slugify } = require("./path-utils");

const SESSION_VERSION = 1;

function timestampForFile(date = new Date()) {
  return date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function defaultSessionRoot(rootDir) {
  return path.join(rootDir, ".swipesheet");
}

function sessionPathFor(rootDir, sessionId) {
  return path.join(defaultSessionRoot(rootDir), "sessions", `${sessionId}.json`);
}

function createSession(options) {
  const rootDir = options.rootDir || process.cwd();
  const title = options.title || "Image review";
  const slug = slugify(options.sessionName || title, "review");
  const sessionId = `${timestampForFile()}-${slug}`;
  const sessionFile = sessionPathFor(rootDir, sessionId);

  const decisions = {};
  for (const item of options.items) {
    decisions[item.id] = {
      status: "unreviewed",
      note: item.note || "",
      reviewedAt: null,
    };
  }

  const session = {
    version: SESSION_VERSION,
    id: sessionId,
    title,
    prompt: options.prompt || "",
    rootDir,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    finishedAt: null,
    currentIndex: 0,
    batchSize: options.batchSize || 20,
    items: options.items,
    decisions,
  };

  saveSession(sessionFile, session);
  return { session, sessionFile };
}

function loadSession(sessionFile) {
  const absolutePath = path.resolve(sessionFile);
  const session = JSON.parse(fs.readFileSync(absolutePath, "utf8"));
  if (!session.version || !session.items || !session.decisions) {
    throw new Error(`Invalid session file: ${absolutePath}`);
  }
  return { session, sessionFile: absolutePath };
}

function saveSession(sessionFile, session) {
  ensureDir(path.dirname(sessionFile));
  session.updatedAt = new Date().toISOString();
  fs.writeFileSync(sessionFile, `${JSON.stringify(session, null, 2)}\n`);
}

function summarizeProgress(session) {
  const counts = {
    total: session.items.length,
    reviewed: 0,
    unreviewed: 0,
    use: 0,
    reject: 0,
    maybe: 0,
  };

  for (const item of session.items) {
    const decision = session.decisions[item.id] || { status: "unreviewed" };
    if (decision.status === "unreviewed") {
      counts.unreviewed += 1;
    } else {
      counts.reviewed += 1;
      if (counts[decision.status] !== undefined) counts[decision.status] += 1;
    }
  }

  return counts;
}

function setDecision(session, payload) {
  const item = session.items.find((entry) => entry.id === payload.id);
  if (!item) throw new Error(`Unknown image id: ${payload.id}`);

  const allowed = new Set(["unreviewed", "use", "reject", "maybe"]);
  const status = payload.status || "unreviewed";
  if (!allowed.has(status)) {
    throw new Error(`Invalid status: ${status}`);
  }

  session.decisions[item.id] = {
    status,
    note: typeof payload.note === "string" ? payload.note : session.decisions[item.id]?.note || "",
    reviewedAt: status === "unreviewed" ? null : new Date().toISOString(),
  };

  if (Number.isInteger(payload.currentIndex)) {
    session.currentIndex = Math.max(0, Math.min(session.items.length - 1, payload.currentIndex));
  }

  session.finishedAt = null;
  return session.decisions[item.id];
}

function setNote(session, payload) {
  const item = session.items.find((entry) => entry.id === payload.id);
  if (!item) throw new Error(`Unknown image id: ${payload.id}`);
  const existing = session.decisions[item.id] || { status: "unreviewed", reviewedAt: null };
  session.decisions[item.id] = {
    ...existing,
    note: typeof payload.note === "string" ? payload.note : "",
  };
  return session.decisions[item.id];
}

module.exports = {
  createSession,
  defaultSessionRoot,
  loadSession,
  saveSession,
  sessionPathFor,
  setDecision,
  setNote,
  summarizeProgress,
};

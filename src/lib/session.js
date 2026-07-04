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

function latestSessionPath(rootDir) {
  return path.join(defaultSessionRoot(rootDir), "sessions", "latest.json");
}

function assertUniqueIds(entries, label) {
  const seen = new Set();
  for (const entry of entries || []) {
    if (!entry || !entry.id) throw new Error(`Invalid ${label}: missing id`);
    if (seen.has(entry.id)) throw new Error(`Duplicate ${label} id: ${entry.id}`);
    seen.add(entry.id);
  }
}

function withSkippedAction(actions) {
  const values = Array.isArray(actions) ? actions.filter(Boolean) : [];
  return values.includes("skipped") ? values : [...values, "skipped"];
}

function newestTimestampedSession(sessionDir) {
  if (!fs.existsSync(sessionDir)) return null;
  const candidates = fs
    .readdirSync(sessionDir)
    .filter((name) => name.endsWith(".json") && name !== "latest.json")
    .map((name) => path.join(sessionDir, name))
    .filter((filePath) => fs.statSync(filePath).isFile())
    .sort((a, b) => path.basename(b).localeCompare(path.basename(a)));
  return candidates[0] || null;
}

function resolveSessionFile(sessionFile) {
  const absolutePath = path.resolve(sessionFile);
  if (path.basename(absolutePath) !== "latest.json") return absolutePath;

  try {
    if (fs.lstatSync(absolutePath).isSymbolicLink()) {
      return fs.realpathSync.native(absolutePath);
    }
  } catch (_error) {
    // Fall through to the copy-fallback behavior below.
  }

  return newestTimestampedSession(path.dirname(absolutePath)) || absolutePath;
}

function linkLatestSession(rootDir, sessionFile) {
  const latestPath = latestSessionPath(rootDir);
  ensureDir(path.dirname(latestPath));

  try {
    if (fs.existsSync(latestPath) || fs.lstatSync(latestPath).isSymbolicLink()) fs.unlinkSync(latestPath);
  } catch (_error) {
    // Missing latest links are fine.
  }

  try {
    fs.symlinkSync(path.basename(sessionFile), latestPath);
  } catch (_error) {
    fs.copyFileSync(sessionFile, latestPath);
  }
}

function createSession(options) {
  const rootDir = options.rootDir || process.cwd();
  const title = options.title || "Image review";
  const slug = slugify(options.sessionName || title, "review");
  const sessionId = `${timestampForFile()}-${slug}`;
  const sessionFile = sessionPathFor(rootDir, sessionId);
  assertUniqueIds(options.items, "item");

  const decisions = {};
  for (const item of options.items) {
    decisions[item.id] = {
      status: "unreviewed",
      note: item.note || "",
      reviewedAt: null,
    };
  }

  const groups = Array.isArray(options.groups) ? options.groups : [];
  assertUniqueIds(groups, "group");
  const groupDecisions = {};
  for (const group of groups) {
    groupDecisions[group.id] = {
      status: "unreviewed",
      note: "",
      reviewedAt: null,
      itemOrder: Array.isArray(group.itemIds) ? group.itemIds : [],
    };
  }

  const session = {
    version: SESSION_VERSION,
    id: sessionId,
    kind: options.kind || "image_review",
    reviewType: options.reviewType || (groups.length > 0 ? "grouped" : "multi_select"),
    actions: options.actions || ["use", "maybe", "reject"],
    itemActions: options.itemActions || ["use", "maybe", "reject"],
    groupActions: groups.length > 0 ? withSkippedAction(options.groupActions || []) : options.groupActions || [],
    metadata: options.metadata || {},
    title,
    prompt: options.prompt || "",
    rootDir,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    finishedAt: null,
    currentIndex: 0,
    batchSize: options.batchSize || 20,
    items: options.items,
    groups,
    decisions,
    groupDecisions,
  };

  saveSession(sessionFile, session);
  linkLatestSession(rootDir, sessionFile);
  return { session, sessionFile };
}

function loadSession(sessionFile) {
  const absolutePath = resolveSessionFile(sessionFile);
  const session = JSON.parse(fs.readFileSync(absolutePath, "utf8"));
  if (!session.version || !session.items || !session.decisions) {
    throw new Error(`Invalid session file: ${absolutePath}`);
  }
  if (session.version > SESSION_VERSION) {
    throw new Error(`Unsupported session version ${session.version}: ${absolutePath}`);
  }
  assertUniqueIds(session.items, "item");
  assertUniqueIds(session.groups || [], "group");
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

  const allowed = new Set(["unreviewed", ...(session.itemActions || ["use", "reject", "maybe"])]);
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
  latestSessionPath,
  loadSession,
  resolveSessionFile,
  saveSession,
  sessionPathFor,
  setDecision,
  setNote,
  summarizeProgress,
};

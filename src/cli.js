"use strict";

const { discoverImages } = require("./lib/images");
const { buildExport } = require("./lib/exporter");
const { createSession, loadSession } = require("./lib/session");
const { buildNativeApp, launchNativeReviewer } = require("./native");

function printHelp() {
  console.log(`SwipeSheet

Usage:
  swipesheet review <image-or-folder-or-manifest...> [options]
  swipesheet resume <session-json> [options]
  swipesheet export <session-json> [--format agent|json]
  swipesheet build-native

Review options:
  --title <text>          Human-readable review title
  --prompt <text>         Review intent copied into the final export
  --session <name>        Short name used in the session filename
  --batch-size <number>   Number of images shown in the queue strip (default: 20)
  --limit <number>        Review only the first N discovered images

Examples:
  swipesheet review ~/Desktop/PHOTO --title "Portfolio scenic selects"
  swipesheet review out/candidates --prompt "Pick one canonical identity per persona"
  swipesheet export .swipesheet/sessions/20260625T190000Z-review.json
`);
}

function parseArgs(argv) {
  const positional = [];
  const options = {};

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) {
      positional.push(arg);
      continue;
    }

    const key = arg.slice(2);
    if (["force"].includes(key)) {
      options[key] = true;
      continue;
    }

    const next = argv[index + 1];
    if (next === undefined || next.startsWith("--")) {
      throw new Error(`Missing value for --${key}`);
    }
    options[key] = next;
    index += 1;
  }

  return { positional, options };
}

function numberOption(options, key, fallback) {
  if (options[key] === undefined) return fallback;
  const value = Number(options[key]);
  if (!Number.isFinite(value) || value <= 0) throw new Error(`--${key} must be a positive number`);
  return value;
}

async function reviewCommand(argv) {
  const { positional: sources, options } = parseArgs(argv);
  if (sources.length === 0) {
    printHelp();
    throw new Error("Provide at least one image, folder, or manifest to review.");
  }

  const rootDir = process.cwd();
  const limit = numberOption(options, "limit", Infinity);
  const batchSize = numberOption(options, "batch-size", 20);
  const items = discoverImages(sources, { rootDir, limit });

  if (items.length === 0) {
    throw new Error("No supported images were found.");
  }

  const { session, sessionFile } = createSession({
    items,
    rootDir,
    title: options.title || "Image review",
    prompt: options.prompt || "",
    sessionName: options.session || options.title,
    batchSize,
  });

  await serveSession({ session, sessionFile, options });
}

async function resumeCommand(argv) {
  const { positional, options } = parseArgs(argv);
  if (positional.length !== 1) {
    printHelp();
    throw new Error("Provide exactly one session JSON file to resume.");
  }
  const { session, sessionFile } = loadSession(positional[0]);
  await serveSession({ session, sessionFile, options });
}

async function serveSession({ session, sessionFile, options }) {
  const rootDir = session.rootDir || process.cwd();

  console.log("");
  console.log("SwipeSheet is opening a native macOS review window.");
  console.log(`Session:      ${session.title}`);
  console.log(`Images:       ${session.items.length}`);
  console.log(`Session file: ${sessionFile}`);
  console.log("");
  console.log("Keyboard: x reject, y use, m maybe, n note, left/right navigate.");
  console.log("Finish from the app to copy the AI-agent-ready export.");

  await launchNativeReviewer({ rootDir, sessionFile });
}

function exportCommand(argv) {
  const { positional, options } = parseArgs(argv);
  if (positional.length !== 1) {
    printHelp();
    throw new Error("Provide exactly one session JSON file to export.");
  }
  const { session } = loadSession(positional[0]);
  process.stdout.write(buildExport(session, { format: options.format || "agent" }));
}

async function main(argv) {
  const [command, ...rest] = argv;

  if (!command || command === "help" || command === "--help" || command === "-h") {
    printHelp();
    return;
  }

  if (command === "review") return reviewCommand(rest);
  if (command === "resume") return resumeCommand(rest);
  if (command === "export") return exportCommand(rest);
  if (command === "build-native") {
    const { options } = parseArgs(rest);
    const binary = buildNativeApp(process.cwd(), { force: Boolean(options.force) });
    console.log(binary);
    return;
  }

  printHelp();
  throw new Error(`Unknown command: ${command}`);
}

module.exports = {
  main,
  parseArgs,
};

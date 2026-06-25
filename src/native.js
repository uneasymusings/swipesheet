"use strict";

const fs = require("fs");
const path = require("path");
const { spawn, spawnSync } = require("child_process");
const { defaultSessionRoot } = require("./lib/session");

const SOURCE_PATH = path.resolve(__dirname, "..", "native", "macos", "ImagePickerApp.swift");

function nativeBinaryPath(rootDir) {
  return path.join(defaultSessionRoot(rootDir), "bin", "swipesheet-macos");
}

function needsBuild(sourcePath, binaryPath) {
  if (!fs.existsSync(binaryPath)) return true;
  const sourceStat = fs.statSync(sourcePath);
  const binaryStat = fs.statSync(binaryPath);
  return sourceStat.mtimeMs > binaryStat.mtimeMs || binaryStat.size === 0;
}

function buildNativeApp(rootDir, options = {}) {
  if (process.platform !== "darwin") {
    throw new Error("The native reviewer currently requires macOS.");
  }

  const binaryPath = nativeBinaryPath(rootDir);
  const moduleCachePath = path.join(defaultSessionRoot(rootDir), "build", "swift-module-cache");
  fs.mkdirSync(path.dirname(binaryPath), { recursive: true });
  fs.mkdirSync(moduleCachePath, { recursive: true });

  if (!options.force && !needsBuild(SOURCE_PATH, binaryPath)) {
    return binaryPath;
  }

  const result = spawnSync("swiftc", ["-O", "-module-cache-path", moduleCachePath, SOURCE_PATH, "-o", binaryPath], {
    encoding: "utf8",
    stdio: options.quiet ? "pipe" : "inherit",
  });

  if (result.status !== 0) {
    const output = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
    throw new Error(output || "Failed to build the native macOS reviewer.");
  }

  return binaryPath;
}

function launchNativeReviewer({ rootDir, sessionFile }) {
  const binaryPath = buildNativeApp(rootDir);

  return new Promise((resolve, reject) => {
    const child = spawn(binaryPath, [sessionFile], {
      stdio: "inherit",
      cwd: rootDir,
    });

    child.on("error", reject);
    child.on("exit", (code, signal) => {
      if (signal) {
        reject(new Error(`Native reviewer exited with signal ${signal}`));
      } else if (code !== 0) {
        reject(new Error(`Native reviewer exited with code ${code}`));
      } else {
        resolve();
      }
    });
  });
}

module.exports = {
  buildNativeApp,
  launchNativeReviewer,
  nativeBinaryPath,
};

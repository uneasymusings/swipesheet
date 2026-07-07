"use strict";

const fs = require("fs");
const path = require("path");
const { walkImages } = require("./images");
const { normalizePath, slugify } = require("./path-utils");

const PATH_FIELDS = ["path", "filePath", "fullPath", "originalPath", "original", "src", "url"];
const LOCAL_PATH_FIELDS = ["path", "filePath", "fullPath", "originalPath", "original", "src"];
const ITEM_ARRAY_FIELDS = ["items", "images", "slides", "media", "assets", "files"];

function firstValue(raw, fields) {
  for (const field of fields) {
    if (raw && raw[field] !== undefined && raw[field] !== null && raw[field] !== "") return raw[field];
  }
  return undefined;
}

function firstArray(raw, fields) {
  for (const field of fields) {
    if (raw && Array.isArray(raw[field])) return raw[field];
  }
  return [];
}

function objectMetadata(raw, excluded = new Set()) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const metadata = { ...(raw.metadata && typeof raw.metadata === "object" && !Array.isArray(raw.metadata) ? raw.metadata : {}) };
  for (const [key, value] of Object.entries(raw)) {
    if (excluded.has(key) || key === "metadata") continue;
    if (metadata[key] === undefined) metadata[key] = value;
  }
  return metadata;
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function buildPersonaManifest(source, options = {}) {
  const rootDir = options.rootDir || process.cwd();
  const sourcePath = normalizePath(source, rootDir);
  const stat = fs.statSync(sourcePath);
  const groups = [];

  if (stat.isDirectory()) {
    const entries = fs.readdirSync(sourcePath, { withFileTypes: true }).sort((a, b) =>
      a.name.localeCompare(b.name, undefined, { numeric: true })
    );
    const directories = entries.filter((entry) => entry.isDirectory() && !entry.name.startsWith("."));
    const imageRoots = directories.length > 0 ? directories.map((entry) => path.join(sourcePath, entry.name)) : [sourcePath];

    for (const imageRoot of imageRoots) {
      const personaId = path.basename(imageRoot);
      const images = walkImages(imageRoot).map((item, index) => ({
        path: item.path,
        label: `${personaId} candidate ${index + 1}`,
        metadata: {
          personaId,
          candidateIndex: index + 1,
          role: "persona_reference",
        },
      }));
      if (images.length === 0) continue;
      groups.push({
        id: personaId,
        label: personaId,
        metadata: {
          personaId,
          description: `Candidate reference images for ${personaId}.`,
          objective: "Choose the single strongest canonical persona reference.",
          itemActionLabels: {
            use: "Canonical",
            maybe: "Keeper",
            reject: "Drop",
          },
          groupActionLabels: {
            approve: `Confirm ${personaId} canonical`,
            request_changes: "Regenerate candidates",
            reject: "Reject persona set",
            skipped: "Skip for now",
          },
          noteRequiredStatuses: ["request_changes"],
          selectionCriteria: [
            "Consistent identity and face structure",
            "Clear, usable image quality",
            "Strong styling for future generation references",
            "No obvious artifacts, bad hands, or distorted anatomy",
          ],
          reviewInstructions: [
            "Mark exactly one candidate as use when possible.",
            "Use maybe for a fallback that needs notes.",
            "Reject identity drift, low quality, or unusable references.",
            "Approve the group when the canonical reference is selected.",
          ],
        },
        constraints: { minSelected: 1, maxSelected: 1 },
        items: images,
      });
    }
  }

  return {
    kind: "autogen_review",
    reviewType: "single_select_per_group",
    actions: ["approve", "request_changes", "reject", "archive"],
    itemActions: ["use", "maybe", "reject"],
    groupActions: ["approve", "request_changes", "reject"],
    groups,
  };
}

function itemFromContentMedia(rawItem, index) {
  if (typeof rawItem === "string") {
    return {
      path: rawItem,
      label: `Slide ${index + 1}`,
      metadata: { slideIndex: index + 1 },
    };
  }

  if (!rawItem || typeof rawItem !== "object") return null;
  const pathValue = firstValue(rawItem, LOCAL_PATH_FIELDS);
  if (!pathValue) return null;

  return {
    id: rawItem.id || rawItem.itemId || rawItem.mediaId || rawItem.slideId || rawItem.externalId || undefined,
    path: pathValue,
    label: rawItem.label || rawItem.title || rawItem.role || `Slide ${index + 1}`,
    note: rawItem.note || rawItem.notes || undefined,
    metadata: {
      slideIndex: rawItem.slideIndex || rawItem.index || index + 1,
      role: rawItem.role || rawItem.slideRole || undefined,
      ...objectMetadata(rawItem, new Set([...PATH_FIELDS, "id", "itemId", "mediaId", "slideId", "label", "title", "note", "notes"])),
    },
  };
}

function contentSetGroup(raw, index, baseDir) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const rawItems = firstArray(raw, ITEM_ARRAY_FIELDS);
  if (rawItems.length === 0) return null;

  const items = rawItems
    .map((item, itemIndex) => {
      const normalized = itemFromContentMedia(item, itemIndex);
      if (!normalized) return null;
      return {
        ...normalized,
        path: normalizePath(normalized.path, baseDir),
      };
    })
    .filter(Boolean);
  if (items.length === 0) return null;

  const id =
    raw.contentSetId ||
    raw.content_set_id ||
    raw.id ||
    raw.externalId ||
    raw.slug ||
    `content_set_${String(index + 1).padStart(4, "0")}`;
  const label = raw.label || raw.title || raw.hook || raw.caption || String(id);

  const metadata = {
    description: "Storyboard or carousel content set prepared by aut0gen.",
    objective: "Approve the creative sequence or request changes before publishing.",
    itemActionLabels: {
      use: "Use slide",
      replace: "Replace slide",
      reject: "Reject slide",
    },
    groupActionLabels: {
      approve_sequence: "Approve sequence",
      needs_reorder: "Needs reorder",
      request_changes: "Request changes",
      reject: "Reject content set",
      skipped: "Skip for now",
    },
    noteRequiredStatuses: ["needs_reorder", "request_changes"],
    selectionCriteria: [
      "The hook is clear in the first slide",
      "The sequence reads in order",
      "The CTA and caption match the creative",
      "Slides match platform and aspect-ratio requirements",
    ],
    reviewInstructions: [
      "Drag the storyboard strip to reorder slides.",
      "Mark individual slides as use, replace, or reject.",
      "Use group actions for the final content-set decision.",
    ],
    ...objectMetadata(raw, new Set([...ITEM_ARRAY_FIELDS, "metadata", "constraints", "id", "label", "title", "name"])),
  };

  return {
    id: String(id),
    label: String(label).slice(0, 120),
    metadata,
    constraints: {
      minSelected: raw.minSelected || raw.min_selected || undefined,
      maxSelected: raw.maxSelected || raw.max_images || raw.accountMaxImages || undefined,
      requiresOrder: true,
      requiredAspect: raw.requiredAspect || raw.aspectRatio || raw.aspect_ratio || undefined,
      ...((raw.constraints && typeof raw.constraints === "object" && !Array.isArray(raw.constraints)) ? raw.constraints : {}),
    },
    items,
  };
}

function collectContentSetGroups(node, groups, seen, baseDir) {
  if (!node || typeof node !== "object") return;

  if (Array.isArray(node)) {
    for (const child of node) collectContentSetGroups(child, groups, seen, baseDir);
    return;
  }

  const group = contentSetGroup(node, groups.length, baseDir);
  if (group && !seen.has(group.id)) {
    seen.add(group.id);
    groups.push(group);
    return;
  }

  for (const value of Object.values(node)) {
    if (value && typeof value === "object") collectContentSetGroups(value, groups, seen, baseDir);
  }
}

function buildContentSetsManifest(source, options = {}) {
  const rootDir = options.rootDir || process.cwd();
  const sourcePath = normalizePath(source, rootDir);
  const baseDir = path.dirname(sourcePath);
  const parsed = JSON.parse(fs.readFileSync(sourcePath, "utf8"));
  const groups = [];
  collectContentSetGroups(parsed, groups, new Set(), baseDir);

  return {
    kind: "autogen_review",
    reviewType: "storyboard",
    actions: ["approve", "request_changes", "reject", "archive"],
    itemActions: ["use", "replace", "reject"],
    groupActions: ["approve_sequence", "needs_reorder", "request_changes", "reject"],
    metadata: {
      source: sourcePath,
      sourceType: "autogen_pipeline_memory",
    },
    groups,
  };
}

function buildAutogenManifest(kind, source, options = {}) {
  if (kind === "personas") return buildPersonaManifest(source, options);
  if (kind === "content-sets") return buildContentSetsManifest(source, options);
  throw new Error(`Unknown autogen manifest kind: ${kind}`);
}

function writeAutogenManifest(kind, source, outFile, options = {}) {
  const rootDir = options.rootDir || process.cwd();
  const outPath = normalizePath(outFile || `.autogen/reviews/${slugify(kind, "review")}.json`, rootDir);
  const manifest = buildAutogenManifest(kind, source, { rootDir });
  writeJson(outPath, manifest);
  return { outPath, manifest };
}

module.exports = {
  buildAutogenManifest,
  buildContentSetsManifest,
  buildPersonaManifest,
  writeAutogenManifest,
};

"use strict";

const fs = require("fs");
const path = require("path");
const {
  IMAGE_EXTENSIONS,
  MANIFEST_EXTENSIONS,
  hashString,
  normalizePath,
  slugify,
  toPosixPath,
} = require("./path-utils");

const PATH_FIELDS = ["path", "filePath", "fullPath", "originalPath", "original", "src", "url"];
const NOTE_FIELDS = ["note", "notes", "feedback"];
const ITEM_ARRAY_FIELDS = ["items", "images", "slides", "media", "assets", "files"];
const TOP_LEVEL_ITEM_ARRAY_FIELDS = ["images", "items", "files", "picks", "results", "slides", "media", "assets"];
const STRUCTURAL_ITEM_FIELDS = new Set([
  "id",
  "itemId",
  "assetId",
  "mediaId",
  "slideId",
  "label",
  "title",
  "name",
  "folder",
  "roll",
  "group",
  "groupId",
  "groupLabel",
  "persona",
  "order",
  "sequence",
]);
const STRUCTURAL_GROUP_FIELDS = new Set([
  "id",
  "groupId",
  "label",
  "title",
  "name",
  "items",
  "images",
  "slides",
  "media",
  "assets",
  "files",
  "metadata",
  "constraints",
  "reviewType",
  "mode",
  "type",
]);

function isImagePath(filePath, extensions = IMAGE_EXTENSIONS) {
  return extensions.has(path.extname(filePath).toLowerCase());
}

function isManifestPath(filePath) {
  return MANIFEST_EXTENSIONS.has(path.extname(filePath).toLowerCase());
}

function tryRealPath(filePath) {
  try {
    return fs.realpathSync.native(filePath);
  } catch (_error) {
    return path.resolve(filePath);
  }
}

function walkImages(dirPath, options = {}) {
  const extensions = options.extensions || IMAGE_EXTENSIONS;
  const includeHidden = Boolean(options.includeHidden);
  const found = [];

  function visit(current) {
    const entries = fs.readdirSync(current, { withFileTypes: true }).sort((a, b) =>
      a.name.localeCompare(b.name, undefined, { numeric: true })
    );

    for (const entry of entries) {
      if (!includeHidden && entry.name.startsWith(".")) continue;
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        visit(fullPath);
      } else if (entry.isFile() && isImagePath(fullPath, extensions)) {
        found.push({ path: fullPath });
      }
    }
  }

  visit(dirPath);
  return found;
}

function valueLooksLikePath(value) {
  if (typeof value !== "string") return false;
  const trimmed = value.trim();
  if (!trimmed) return false;
  if (/^https?:\/\//i.test(trimmed)) return false;
  return trimmed.startsWith("/") || trimmed.startsWith("~/") || trimmed.includes(path.sep) || isImagePath(trimmed);
}

function firstValue(raw, fields) {
  for (const field of fields) {
    if (raw[field] !== undefined && raw[field] !== null && raw[field] !== "") return raw[field];
  }
  return undefined;
}

function firstArray(raw, fields) {
  for (const field of fields) {
    if (Array.isArray(raw[field])) return raw[field];
  }
  return [];
}

function asStringArray(value) {
  if (!Array.isArray(value)) return undefined;
  return value.filter((entry) => typeof entry === "string" && entry.trim()).map((entry) => entry.trim());
}

function asPlainObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function numberFrom(value) {
  if (value === undefined || value === null || value === "") return undefined;
  const number = Number(value);
  return Number.isFinite(number) ? number : undefined;
}

function metadataFrom(raw, reserved = new Set()) {
  const metadata = { ...asPlainObject(raw.metadata) };

  for (const [key, value] of Object.entries(raw)) {
    if (reserved.has(key) || PATH_FIELDS.includes(key) || NOTE_FIELDS.includes(key) || key === "metadata") continue;
    if (metadata[key] === undefined) metadata[key] = value;
  }

  return metadata;
}

function normalizeManifestItem(rawItem, baseDir, context = {}) {
  if (typeof rawItem === "string") {
    return {
      path: normalizePath(rawItem, baseDir),
      groupId: context.groupId,
      groupLabel: context.groupLabel,
      order: context.order,
    };
  }

  if (!rawItem || typeof rawItem !== "object") return null;

  const pathValue = firstValue(rawItem, PATH_FIELDS);

  if (!valueLooksLikePath(pathValue)) return null;

  const metadata = metadataFrom(rawItem, STRUCTURAL_ITEM_FIELDS);
  const order =
    numberFrom(rawItem.order) ||
    numberFrom(rawItem.slideIndex) ||
    numberFrom(rawItem.sequence) ||
    numberFrom(metadata.order) ||
    numberFrom(metadata.slideIndex) ||
    context.order;

  const normalized = {
    sourceId:
      rawItem.id ||
      rawItem.itemId ||
      rawItem.assetId ||
      rawItem.mediaId ||
      rawItem.slideId ||
      rawItem.externalId ||
      undefined,
    path: normalizePath(pathValue, baseDir),
    label:
      rawItem.label ||
      rawItem.title ||
      rawItem.name ||
      rawItem.folder ||
      rawItem.roll ||
      rawItem.group ||
      rawItem.persona ||
      context.itemLabel ||
      undefined,
    note: firstValue(rawItem, NOTE_FIELDS),
    groupId: rawItem.groupId || rawItem.group || context.groupId,
    groupLabel: rawItem.groupLabel || context.groupLabel,
    order,
    metadata,
  };

  return normalized;
}

function groupIdFor(rawGroup, index) {
  const value =
    rawGroup.id ||
    rawGroup.groupId ||
    rawGroup.contentSetId ||
    rawGroup.personaId ||
    rawGroup.briefId ||
    rawGroup.externalId ||
    rawGroup.label ||
    rawGroup.title ||
    rawGroup.name;
  return value ? String(value) : `group_${String(index + 1).padStart(4, "0")}`;
}

function normalizeManifestGroup(rawGroup, baseDir, index, manifestDefaults = {}) {
  if (!rawGroup || typeof rawGroup !== "object") return null;

  const id = groupIdFor(rawGroup, index);
  const label = rawGroup.label || rawGroup.title || rawGroup.name || rawGroup.personaId || rawGroup.contentSetId || id;
  const rawItems = firstArray(rawGroup, ITEM_ARRAY_FIELDS);
  const metadata = metadataFrom(rawGroup, STRUCTURAL_GROUP_FIELDS);
  const constraints = asPlainObject(rawGroup.constraints);
  const reviewType = rawGroup.reviewType || rawGroup.mode || rawGroup.type || manifestDefaults.reviewType;

  const group = {
    id,
    index: index + 1,
    label: String(label),
    reviewType,
    metadata,
    constraints,
    itemIds: [],
  };

  const items = rawItems
    .map((item, itemIndex) =>
      normalizeManifestItem(item, baseDir, {
        groupId: id,
        groupLabel: String(label),
        order: itemIndex + 1,
      })
    )
    .filter(Boolean);

  return { group, items };
}

function parseDelimitedManifest(filePath) {
  const baseDir = path.dirname(filePath);
  const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);
  const items = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const columns = trimmed.split(/\t|,/).map((value) => value.trim()).filter(Boolean);
    const pathColumn = columns.find(valueLooksLikePath);
    if (!pathColumn) continue;

    items.push({
      path: normalizePath(pathColumn, baseDir),
      label: columns.length > 1 ? columns.find((value) => value !== pathColumn) : undefined,
    });
  }

  return items;
}

function parseJsonManifest(filePath) {
  return parseJsonReviewManifest(filePath).items;
}

function parseJsonReviewManifest(filePath) {
  const baseDir = path.dirname(filePath);
  const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
  const review = {
    kind: Array.isArray(parsed) ? undefined : parsed.kind,
    reviewType: Array.isArray(parsed) ? undefined : parsed.reviewType || parsed.mode || parsed.type,
    actions: Array.isArray(parsed) ? undefined : asStringArray(parsed.actions),
    itemActions: Array.isArray(parsed) ? undefined : asStringArray(parsed.itemActions),
    groupActions: Array.isArray(parsed) ? undefined : asStringArray(parsed.groupActions),
    metadata: Array.isArray(parsed) ? {} : asPlainObject(parsed.metadata),
    groups: [],
    items: [],
  };

  if (!Array.isArray(parsed) && Array.isArray(parsed.groups)) {
    for (let index = 0; index < parsed.groups.length; index += 1) {
      const normalized = normalizeManifestGroup(parsed.groups[index], baseDir, index, review);
      if (!normalized) continue;
      review.groups.push(normalized.group);
      review.items.push(...normalized.items);
    }
    return review;
  }

  const rawItems = Array.isArray(parsed) ? parsed : firstArray(parsed, TOP_LEVEL_ITEM_ARRAY_FIELDS);

  if (!Array.isArray(rawItems)) {
    throw new Error(`JSON manifest must be an array or contain images/items/files/picks/results: ${filePath}`);
  }

  review.items = rawItems.map((item, index) => normalizeManifestItem(item, baseDir, { order: index + 1 })).filter(Boolean);
  return review;
}

function parseManifest(filePath) {
  return parseReviewManifest(filePath).items;
}

function parseReviewManifest(filePath) {
  if (path.extname(filePath).toLowerCase() === ".json") {
    return parseJsonReviewManifest(filePath);
  }

  return {
    kind: undefined,
    reviewType: undefined,
    actions: undefined,
    itemActions: undefined,
    groupActions: undefined,
    metadata: {},
    groups: [],
    items: parseDelimitedManifest(filePath),
  };
}

function itemLabel(filePath, rootDir, providedLabel) {
  if (providedLabel) return String(providedLabel);
  const parent = path.basename(path.dirname(filePath));
  if (parent && parent !== path.basename(rootDir)) return parent;
  return path.basename(rootDir);
}

function uniqueId(value, seen) {
  const base = String(value || "").trim() || slugify(value, "item");
  if (!seen.has(base)) {
    seen.add(base);
    return base;
  }

  let suffix = 2;
  while (seen.has(`${base}__${suffix}`)) suffix += 1;
  const unique = `${base}__${suffix}`;
  seen.add(unique);
  return unique;
}

function mergeReviewOptions(target, manifest) {
  for (const key of ["kind", "reviewType"]) {
    if (!target[key] && manifest[key]) target[key] = manifest[key];
  }

  for (const key of ["actions", "itemActions", "groupActions"]) {
    if (!target[key] && Array.isArray(manifest[key]) && manifest[key].length > 0) {
      target[key] = manifest[key];
    }
  }

  if (manifest.metadata && Object.keys(manifest.metadata).length > 0) {
    target.metadata = { ...(target.metadata || {}), ...manifest.metadata };
  }
}

function discoverReviewSource(sources, options = {}) {
  const rootDir = options.rootDir || process.cwd();
  const limit = Number.isFinite(options.limit) && options.limit > 0 ? options.limit : Infinity;
  const discovered = [];
  const groupDefinitions = [];
  const review = {
    kind: undefined,
    reviewType: undefined,
    actions: undefined,
    itemActions: undefined,
    groupActions: undefined,
    metadata: {},
  };
  const seenGroupIds = new Set();

  for (const source of sources) {
    const sourcePath = normalizePath(source, rootDir);
    if (!fs.existsSync(sourcePath)) {
      throw new Error(`Source does not exist: ${sourcePath}`);
    }

    const stat = fs.statSync(sourcePath);
    if (stat.isDirectory()) {
      discovered.push(...walkImages(sourcePath, options));
    } else if (stat.isFile() && isImagePath(sourcePath, options.extensions || IMAGE_EXTENSIONS)) {
      discovered.push({ path: sourcePath });
    } else if (stat.isFile() && isManifestPath(sourcePath)) {
      const manifest = parseReviewManifest(sourcePath);
      mergeReviewOptions(review, manifest);

      const groupIdMap = new Map();
      for (const group of manifest.groups) {
        const id = uniqueId(group.id, seenGroupIds);
        groupIdMap.set(group.id, id);
        groupDefinitions.push({
          ...group,
          id,
          itemIds: [],
        });
      }

      for (const item of manifest.items) {
        const groupId = item.groupId ? groupIdMap.get(item.groupId) || item.groupId : undefined;
        discovered.push({
          ...item,
          groupId,
          groupLabel:
            item.groupLabel ||
            groupDefinitions.find((group) => group.id === groupId)?.label ||
            undefined,
        });
      }
    } else {
      throw new Error(`Unsupported source. Expected an image, directory, or manifest: ${sourcePath}`);
    }

    if (discovered.length >= limit) break;
  }

  const seen = new Set();
  const seenItemIds = new Set();
  const items = [];
  const groupsById = new Map(groupDefinitions.map((group) => [group.id, group]));

  for (const rawItem of discovered) {
    if (items.length >= limit) break;
    const absolutePath = normalizePath(rawItem.path, rootDir);
    if (!fs.existsSync(absolutePath)) continue;
    const stat = fs.statSync(absolutePath);
    if (!stat.isFile() || !isImagePath(absolutePath, options.extensions || IMAGE_EXTENSIONS)) continue;

    const realPath = tryRealPath(absolutePath);
    const dedupeKey = `${realPath}\u0000${rawItem.groupId || ""}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);

    const index = items.length + 1;
    const extension = path.extname(absolutePath).toLowerCase();
    const relativePath = path.relative(rootDir, absolutePath);
    const generatedId = `img_${String(index).padStart(5, "0")}_${hashString(`${realPath}:${rawItem.groupId || ""}`)}`;
    const id = rawItem.sourceId ? uniqueId(rawItem.sourceId, seenItemIds) : generatedId;
    seenItemIds.add(id);

    if (rawItem.groupId && !groupsById.has(rawItem.groupId)) {
      const label = rawItem.groupLabel || rawItem.groupId;
      const group = {
        id: rawItem.groupId,
        index: groupsById.size + 1,
        label,
        reviewType: review.reviewType,
        metadata: {},
        constraints: {},
        itemIds: [],
      };
      groupDefinitions.push(group);
      groupsById.set(group.id, group);
    }

    items.push({
      id,
      index,
      path: absolutePath,
      realPath,
      filename: path.basename(absolutePath),
      extension,
      label: itemLabel(absolutePath, rootDir, rawItem.label),
      relativePath: toPosixPath(relativePath.startsWith("..") ? absolutePath : relativePath),
      note: rawItem.note || "",
      groupId: rawItem.groupId,
      groupLabel: rawItem.groupLabel,
      order: rawItem.order || index,
      metadata: rawItem.metadata || {},
    });

    if (rawItem.groupId && groupsById.has(rawItem.groupId)) {
      groupsById.get(rawItem.groupId).itemIds.push(id);
    }
  }

  const groups = groupDefinitions
    .map((group) => ({
      ...group,
      itemIds: group.itemIds.filter((id) => items.some((item) => item.id === id)),
    }))
    .filter((group) => group.itemIds.length > 0);

  return {
    ...review,
    items,
    groups,
  };
}

function discoverImages(sources, options = {}) {
  return discoverReviewSource(sources, options).items;
}

module.exports = {
  discoverImages,
  discoverReviewSource,
  isImagePath,
  parseManifest,
  parseReviewManifest,
  walkImages,
};

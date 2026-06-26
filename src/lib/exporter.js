"use strict";

function decisionFor(session, item) {
  return session.decisions[item.id] || { status: "unreviewed", note: "" };
}

function groupDecisionFor(session, group) {
  return (
    (session.groupDecisions && session.groupDecisions[group.id]) || {
      status: "unreviewed",
      note: "",
      reviewedAt: null,
      itemOrder: Array.isArray(group.itemIds) ? group.itemIds : [],
    }
  );
}

function itemMapFor(session) {
  return new Map(session.items.map((item) => [item.id, item]));
}

function orderedItemsForGroup(session, group) {
  const byId = itemMapFor(session);
  const groupDecision = groupDecisionFor(session, group);
  const order = Array.isArray(groupDecision.itemOrder) && groupDecision.itemOrder.length > 0 ? groupDecision.itemOrder : group.itemIds;
  return order.map((id) => byId.get(id)).filter(Boolean);
}

function imageLine(item, decision) {
  const parts = [`#${String(item.index).padStart(4, "0")}`, item.label, item.filename].filter(Boolean);
  const note = decision.note ? `\n   note: ${decision.note.trim()}` : "";
  return `- ${parts.join(" | ")}\n   path: ${item.path}${note}`;
}

function compactMetadata(metadata = {}) {
  const entries = Object.entries(metadata).filter(([, value]) => value !== undefined && value !== null && value !== "");
  if (entries.length === 0) return "";
  return entries
    .slice(0, 8)
    .map(([key, value]) => `${key}: ${typeof value === "object" ? JSON.stringify(value) : value}`)
    .join(" | ");
}

function buildAgentExport(session) {
  const groups = {
    use: [],
    maybe: [],
    reject: [],
    unreviewed: [],
    other: [],
  };

  for (const item of session.items) {
    const decision = decisionFor(session, item);
    const status = decision.status || "unreviewed";
    if (groups[status]) {
      groups[status].push({ item, decision });
    } else {
      groups.other.push({ item, decision });
    }
  }

  const lines = [];
  lines.push(`# Image review export: ${session.title}`);
  lines.push("");
  lines.push(`Session: ${session.id}`);
  lines.push(`Reviewed: ${groups.use.length + groups.maybe.length + groups.reject.length + groups.other.length}/${session.items.length}`);
  lines.push(`Use: ${groups.use.length}`);
  lines.push(`Maybe / needs notes: ${groups.maybe.length}`);
  lines.push(`Reject: ${groups.reject.length}`);
  lines.push(`Unreviewed: ${groups.unreviewed.length}`);
  if (Array.isArray(session.groups) && session.groups.length > 0) {
    lines.push(`Groups: ${session.groups.length}`);
    if (session.reviewType) lines.push(`Review type: ${session.reviewType}`);
  }

  if (session.prompt) {
    lines.push("");
    lines.push("Original review prompt:");
    lines.push(session.prompt);
  }

  lines.push("");
  lines.push("Instructions for the AI agent:");
  lines.push("- Use the images in the Selected section as approved source material.");
  lines.push("- Treat Maybe items as conditional: follow the note before using them.");
  lines.push("- Do not use rejected images unless I explicitly mention their number later.");
  lines.push("- Preserve the full original paths when copying or wiring assets into another project.");

  lines.push("");
  lines.push("Selected images:");
  if (groups.use.length === 0) {
    lines.push("- None");
  } else {
    for (const entry of groups.use) lines.push(imageLine(entry.item, entry.decision));
  }

  lines.push("");
  lines.push("Maybe / needs changes:");
  if (groups.maybe.length === 0) {
    lines.push("- None");
  } else {
    for (const entry of groups.maybe) lines.push(imageLine(entry.item, entry.decision));
  }

  if (groups.other.length > 0) {
    lines.push("");
    lines.push("Other item decisions:");
    for (const entry of groups.other) {
      lines.push(`${imageLine(entry.item, entry.decision)}\n   status: ${entry.decision.status}`);
    }
  }

  const rejectedWithNotes = groups.reject.filter((entry) => entry.decision.note);
  if (rejectedWithNotes.length > 0) {
    lines.push("");
    lines.push("Rejected images with notes:");
    for (const entry of rejectedWithNotes) lines.push(imageLine(entry.item, entry.decision));
  }

  lines.push("");
  lines.push("Rejected image numbers:");
  lines.push(
    groups.reject.length === 0
      ? "- None"
      : groups.reject.map((entry) => `#${String(entry.item.index).padStart(4, "0")}`).join(", ")
  );

  if (Array.isArray(session.groups) && session.groups.length > 0) {
    lines.push("");
    lines.push("Groups:");
    for (const group of session.groups) {
      const groupDecision = groupDecisionFor(session, group);
      const items = orderedItemsForGroup(session, group);
      lines.push(`- ${group.id} | ${group.label} | status: ${groupDecision.status || "unreviewed"}`);
      if (group.reviewType) lines.push(`   reviewType: ${group.reviewType}`);
      const metadata = compactMetadata(group.metadata);
      if (metadata) lines.push(`   metadata: ${metadata}`);
      if (Object.keys(group.constraints || {}).length > 0) {
        lines.push(`   constraints: ${JSON.stringify(group.constraints)}`);
      }
      if (groupDecision.note) lines.push(`   note: ${groupDecision.note.trim()}`);
      lines.push(`   ordered items: ${items.map((item) => `#${String(item.index).padStart(4, "0")}`).join(", ") || "None"}`);
    }
  }

  return `${lines.join("\n")}\n`;
}

function resultFor(session, item) {
  const decision = decisionFor(session, item);
  return {
    index: item.index,
    id: item.id,
    groupId: item.groupId,
    status: decision.status || "unreviewed",
    note: decision.note || "",
    reviewedAt: decision.reviewedAt || null,
    label: item.label,
    filename: item.filename,
    path: item.path,
    relativePath: item.relativePath,
    order: item.order,
    metadata: item.metadata || {},
  };
}

function groupResultFor(session, group) {
  const decision = groupDecisionFor(session, group);
  const items = orderedItemsForGroup(session, group);
  return {
    id: group.id,
    index: group.index,
    label: group.label,
    reviewType: group.reviewType || session.reviewType || null,
    status: decision.status || "unreviewed",
    note: decision.note || "",
    reviewedAt: decision.reviewedAt || null,
    itemOrder: items.map((item) => item.id),
    constraints: group.constraints || {},
    metadata: group.metadata || {},
    items: items.map((item) => resultFor(session, item)),
  };
}

function buildJsonExport(session) {
  const results = session.items.map((item) => resultFor(session, item));
  const groups = Array.isArray(session.groups) ? session.groups.map((group) => groupResultFor(session, group)) : [];
  return `${JSON.stringify(
    {
      session: {
        id: session.id,
        title: session.title,
        kind: session.kind || "image_review",
        reviewType: session.reviewType || null,
      },
      groups,
      results,
    },
    null,
    2
  )}\n`;
}

function buildAutogenExport(session) {
  const groups = Array.isArray(session.groups) ? session.groups.map((group) => groupResultFor(session, group)) : [];
  const results = session.items.map((item) => resultFor(session, item));

  return `${JSON.stringify(
    {
      schemaVersion: 1,
      kind: "autogen_review_export",
      session: {
        id: session.id,
        title: session.title,
        prompt: session.prompt || "",
        rootDir: session.rootDir,
        kind: session.kind || "image_review",
        reviewType: session.reviewType || "multi_select",
        createdAt: session.createdAt || null,
        updatedAt: session.updatedAt || null,
        finishedAt: session.finishedAt || null,
        metadata: session.metadata || {},
      },
      actions: {
        item: session.itemActions || ["use", "maybe", "reject"],
        group: session.groupActions || [],
        all: session.actions || [],
      },
      groups,
      results,
    },
    null,
    2
  )}\n`;
}

function buildExport(session, options = {}) {
  if (options.format === "autogen") return buildAutogenExport(session);
  if (options.format === "json") return buildJsonExport(session);
  return buildAgentExport(session);
}

module.exports = {
  buildExport,
};

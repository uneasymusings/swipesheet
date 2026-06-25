"use strict";

function decisionFor(session, item) {
  return session.decisions[item.id] || { status: "unreviewed", note: "" };
}

function imageLine(item, decision) {
  const parts = [`#${String(item.index).padStart(4, "0")}`, item.label, item.filename].filter(Boolean);
  const note = decision.note ? `\n   note: ${decision.note.trim()}` : "";
  return `- ${parts.join(" | ")}\n   path: ${item.path}${note}`;
}

function buildAgentExport(session) {
  const groups = {
    use: [],
    maybe: [],
    reject: [],
    unreviewed: [],
  };

  for (const item of session.items) {
    const decision = decisionFor(session, item);
    groups[decision.status || "unreviewed"].push({ item, decision });
  }

  const lines = [];
  lines.push(`# Image review export: ${session.title}`);
  lines.push("");
  lines.push(`Session: ${session.id}`);
  lines.push(`Reviewed: ${groups.use.length + groups.maybe.length + groups.reject.length}/${session.items.length}`);
  lines.push(`Use: ${groups.use.length}`);
  lines.push(`Maybe / needs notes: ${groups.maybe.length}`);
  lines.push(`Reject: ${groups.reject.length}`);
  lines.push(`Unreviewed: ${groups.unreviewed.length}`);

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

  return `${lines.join("\n")}\n`;
}

function buildJsonExport(session) {
  const results = session.items.map((item) => ({
    index: item.index,
    id: item.id,
    status: decisionFor(session, item).status || "unreviewed",
    note: decisionFor(session, item).note || "",
    label: item.label,
    filename: item.filename,
    path: item.path,
    metadata: item.metadata || {},
  }));
  return `${JSON.stringify({ session: { id: session.id, title: session.title }, results }, null, 2)}\n`;
}

function buildExport(session, options = {}) {
  if (options.format === "json") return buildJsonExport(session);
  return buildAgentExport(session);
}

module.exports = {
  buildExport,
};

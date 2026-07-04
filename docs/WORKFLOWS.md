# Workflow Guide

## Portfolio Contact-Sheet Replacement

The old workflow was:

1. Generate contact sheets.
2. Visually inspect large grids.
3. Tell the coding agent which numbers to use.
4. Have the agent map numbers back to original paths.

The picker collapses that into:

```bash
swipesheet review ~/Desktop/PHOTO \
  --title "Portfolio photo cull" \
  --prompt "Select scenic, no-people film frames for my personal site."
```

During review:

- approve strong frames with `y`
- reject misses with `x`
- use `m` for conditional picks
- write notes for crop, placement, or mood

The final export gives the agent exact paths and instructions.

## Reviewing Existing Contact-Sheet Selects

If another process already made `mapping.json`, use that file directly:

```bash
swipesheet review ~/Desktop/Film\ Contact\ Sheets/mapping.json \
  --title "Final film select pass"
```

This preserves the original paths stored in the mapping file.

## aut0gen Candidate Review

For generated influencer/persona assets:

```bash
swipesheet review out/persona-candidates \
  --title "Persona candidate review" \
  --prompt "Pick one canonical image per persona. Reject identity drift, bad hands, warped faces, and weak styling."
```

Suggested notes:

- "canonical for Mari"
- "good outfit, face drift"
- "use as pose reference only"
- "reject: hand artifacts"

The export is designed so an AI agent can update persona JSON files or pipeline state without needing another explanation pass.

## aut0gen Structured Review

SwipeSheet should act as the visual review layer. Aut0gen remains the source of truth by generating manifests, launching the review, then consuming the exported decisions.

Persona canonical selection:

```bash
swipesheet autogen manifest personas ./references/personas --out .autogen/reviews/personas.json
swipesheet review .autogen/reviews/personas.json \
  --title "Persona canonical review" \
  --prompt "Pick one canonical image per persona. Reject identity drift, artifacts, and weak styling."
swipesheet export .swipesheet/sessions/latest.json --format autogen
```

Content-set or slideshow review:

```bash
swipesheet autogen manifest content-sets .autogen/pipeline-memory.json --out .autogen/reviews/content-sets.json
swipesheet review .autogen/reviews/content-sets.json \
  --title "Content set review" \
  --prompt "Approve ordered sequences, mark replacement slides, and note caption/CTA issues."
swipesheet export .swipesheet/sessions/latest.json --format autogen
```

The aut0gen export includes:

- session IDs and review type
- group IDs such as `contentSetId`, `briefId`, or `personaId`
- ordered group items from the storyboard strip
- item decisions and notes
- group decisions and notes
- manifest metadata and constraints

Agents presenting assets should fill the manifest with `description`, `objective`, `selectionCriteria`, `reviewInstructions`, `checklist`, `actionLabels`, `noteRequiredStatuses`, and per-item `description` fields. Persona sessions should add `personaContext`; publish/content-set sessions should add `consequence`, `accountHandles`, `scheduledLocal`, `creditCostEstimate`, `creditsRemaining`, `publicMediaUrl`, and `videoPath` when available. SwipeSheet surfaces those as the review brief so you know what you are looking at, what decision is expected, and what happens after approval.

Grouped sessions validate before export. Constraints such as `minSelected` and `maxSelected` are checked against the number of `use` decisions, group decisions must be confirmed or explicitly `skipped`, and statuses listed in `noteRequiredStatuses` require notes.

Aut0gen can then apply the review with its own source-of-truth command, for example:

```bash
npm run cli -- review:apply --session .swipesheet/sessions/latest.json
```

## Using From Another Project

First, link the command once from this repo:

```bash
npm link
```

Then run it from the other project's directory:

```bash
swipesheet review ./out/images \
  --title "Approval pass"
```

The session file and native binary cache will be created in that project's `.swipesheet/` directory because the command uses the current working directory as the session root.

## Using With AI CLI Agents

Give the agent a concrete review command and tell it to wait for your review to finish:

```text
Run this from the project root:

swipesheet review <image-folder-or-manifest> \
  --title "<short review name>" \
  --prompt "<selection criteria>"

After I finish the native review window, export the session and use the selected paths and notes to continue.
```

The agent can then run:

```bash
swipesheet export .swipesheet/sessions/<session>.json
```

For scripts or pipeline updates, use JSON:

```bash
swipesheet export .swipesheet/sessions/<session>.json --format json
```

For aut0gen state updates, use the grouped export:

```bash
swipesheet export .swipesheet/sessions/latest.json --format autogen
```

## Resuming

```bash
swipesheet resume .swipesheet/sessions/<session>.json
```

It is also safe to resume the pointer:

```bash
swipesheet resume .swipesheet/sessions/latest.json
```

SwipeSheet resolves `latest.json` to the timestamped session before opening the native app.

## Exporting From the Terminal

```bash
swipesheet export .swipesheet/sessions/<session>.json
```

Use JSON when another script should consume the output:

```bash
swipesheet export .swipesheet/sessions/<session>.json --format json
```

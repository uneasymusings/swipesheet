# Workflow Guide

## Portfolio Contact-Sheet Replacement

The old workflow was:

1. Generate contact sheets.
2. Visually inspect large grids.
3. Tell the coding agent which numbers to use.
4. Have the agent map numbers back to original paths.

The picker collapses that into:

```bash
node ./bin/swipesheet.js review ~/Desktop/PHOTO \
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
node ./bin/swipesheet.js review ~/Desktop/Film\ Contact\ Sheets/mapping.json \
  --title "Final film select pass"
```

This preserves the original paths stored in the mapping file.

## aut0gen Candidate Review

For generated influencer/persona assets:

```bash
node ./bin/swipesheet.js review out/persona-candidates \
  --title "Persona candidate review" \
  --prompt "Pick one canonical image per persona. Reject identity drift, bad hands, warped faces, and weak styling."
```

Suggested notes:

- "canonical for Mari"
- "good outfit, face drift"
- "use as pose reference only"
- "reject: hand artifacts"

The export is designed so an AI agent can update persona JSON files or pipeline state without needing another explanation pass.

## Using From Another Project

From the other project's directory:

```bash
node /Users/ricardoandoni/Developer/CODE/swipesheet/bin/swipesheet.js review ./out/images \
  --title "Approval pass"
```

The session file and native binary cache will be created in that project's `.swipesheet/` directory because the command uses the current working directory as the session root.

## Resuming

```bash
node ./bin/swipesheet.js resume .swipesheet/sessions/<session>.json
```

## Exporting From the Terminal

```bash
node ./bin/swipesheet.js export .swipesheet/sessions/<session>.json
```

Use JSON when another script should consume the output:

```bash
node ./bin/swipesheet.js export .swipesheet/sessions/<session>.json --format json
```

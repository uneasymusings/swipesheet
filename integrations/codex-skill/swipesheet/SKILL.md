---
name: swipesheet
description: Use when a task needs human visual review of local images, generated assets, persona candidates, storyboards, video preview frames, or aut0gen content sets through the SwipeSheet CLI; includes generating manifests, launching reviews, exporting decisions, and applying grouped review state.
metadata:
  short-description: Launch SwipeSheet reviews and consume decisions
---

# SwipeSheet

SwipeSheet is a local macOS visual review layer. Use it when a human should approve, reject, annotate, reorder, or group-review visual assets before an agent continues.

## First Check

From the target project root, verify the command exists:

```bash
swipesheet --help
```

If it is missing, ask the user to link or install SwipeSheet. For local development, the usual setup is:

```bash
cd /path/to/swipesheet
npm link
```

## Basic Review

Launch from the project that owns the assets:

```bash
swipesheet review <image-folder-or-manifest> \
  --title "<short review name>" \
  --prompt "<decision criteria for the human reviewer>"
```

Wait for the human to finish the native window. Then export:

```bash
swipesheet export .swipesheet/sessions/latest.json
```

Use the exported paths, statuses, and notes as the source of truth. Do not infer approval from filenames, folder names, or visual guesses.

## Machine-Readable Exports

For scripts:

```bash
swipesheet export .swipesheet/sessions/latest.json --format json
```

For aut0gen grouped review state:

```bash
swipesheet export .swipesheet/sessions/latest.json --format autogen
```

## Manifest Guidance

Use a flat folder or flat manifest for simple image curation.

Use a grouped manifest when one human decision covers a set of items, such as:

- one canonical persona image per persona
- one post with media, caption, CTA, and publish metadata
- one storyboard/carousel sequence
- one video represented by preview frames plus `group.metadata.videoPath`

Grouped manifests should preserve stable `id`, `group.id`, `metadata.contentSetId`, `metadata.personaId`, `metadata.briefId`, and `metadata.externalId` when those exist.

For video post review, include:

```json
{
  "kind": "autogen_review",
  "reviewType": "post_review",
  "itemActions": ["use", "replace", "reject"],
  "groupActions": ["approve_sequence", "request_changes", "reject"],
  "groups": [
    {
      "id": "content_set_123",
      "label": "Post review",
      "metadata": {
        "contentTypeLabel": "ONE TIKTOK VIDEO (17s) -> @account",
        "contentSetId": "content_set_123",
        "platform": "tiktok",
        "hook": "Opening hook",
        "caption": "Caption text",
        "cta": "Follow for more",
        "videoPath": "out/final.mp4"
      },
      "items": [
        {
          "id": "frame_001",
          "path": "out/frames/frame-001.png",
          "label": "Preview frame",
          "metadata": {
            "slideIndex": 1,
            "role": "preview_frame"
          }
        }
      ]
    }
  ]
}
```

## aut0gen Helpers

Persona review:

```bash
swipesheet autogen manifest personas ./references/personas --out .autogen/reviews/personas.json
swipesheet review .autogen/reviews/personas.json --title "Persona canonical review"
swipesheet export .swipesheet/sessions/latest.json --format autogen
```

Content-set review:

```bash
swipesheet autogen manifest content-sets .autogen/pipeline-memory.json --out .autogen/reviews/content-sets.json
swipesheet review .autogen/reviews/content-sets.json --title "Content set review"
swipesheet export .swipesheet/sessions/latest.json --format autogen
```

If the owning project has an apply command, run it after export, for example:

```bash
npm run cli -- review:apply --session .swipesheet/sessions/latest.json
```

## Rules

- Keep SwipeSheet as the visual review layer, not the source of truth.
- Do not edit `.swipesheet/sessions/latest.json` while the native app is open.
- Preserve exact local paths and stable IDs in manifests and downstream apply steps.
- Use group decisions for post/content-set approval; item decisions are for frames or individual assets.
- If the human asks for changes, consume notes before regenerating or applying state.

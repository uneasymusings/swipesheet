# AI Agent Integration

SwipeSheet is designed to be launched by another AI CLI, then consumed by that same agent after the human finishes reviewing.

The simplest integration is still the CLI. A skill is useful as an instruction wrapper for agents. MCP can wait until SwipeSheet needs a long-running service with tool calls.

## Recommended Setup

From this repository, link the command once:

```bash
npm link
```

From any project where assets are being generated:

```bash
swipesheet review <image-folder-or-manifest> \
  --title "<short review name>" \
  --prompt "<what the human should decide>"
```

SwipeSheet writes sessions in the current project:

```text
.swipesheet/sessions/latest.json
```

After the native review window closes, export the result:

```bash
swipesheet export .swipesheet/sessions/latest.json
```

Use JSON when a script will consume the output:

```bash
swipesheet export .swipesheet/sessions/latest.json --format json
```

Use the aut0gen contract for grouped creative-review state:

```bash
swipesheet export .swipesheet/sessions/latest.json --format autogen
```

## Copy-Paste Prompt For Another Agent

```text
Use SwipeSheet for the human review step.

1. Run this from the project root:

   swipesheet review <image-folder-or-manifest> \
     --title "<short review name>" \
     --prompt "<decision criteria for the reviewer>"

2. Wait until I finish the native review window.
3. Export the latest session:

   swipesheet export .swipesheet/sessions/latest.json

4. Continue using only the exported decisions, notes, and original paths.
   Do not infer approval from filenames or folder names.
```

## Agent Rules

- Preserve original paths, IDs, group IDs, and manifest metadata.
- Do not edit `.swipesheet/sessions/latest.json` while the native app is open.
- Treat `latest.json` as a pointer; `swipesheet resume .swipesheet/sessions/latest.json` and `swipesheet export .swipesheet/sessions/latest.json` resolve it safely.
- Use the text export when the next step is another conversational agent.
- Use `--format json` when the next step is a generic script.
- Use `--format autogen` when the next step applies grouped decisions back into aut0gen state.
- Keep source-of-truth state in the calling project. SwipeSheet is the visual review layer, not the content database.

## Flat Image Review

Use this for portfolio culls, generated stills, thumbnails, or simple image folders:

```bash
swipesheet review ./out/images \
  --title "Image approval pass" \
  --prompt "Pick usable images. Reject artifacts, duplicates, weak composition, or anything that should not ship."
```

The agent should consume:

- selected image paths
- maybe/conditional notes
- rejected image notes
- explicit reviewer instructions in notes

## Grouped Review

Use grouped manifests when one decision covers a set of assets.

Good grouped-review cases:

- pick one canonical persona reference per persona
- approve a post with media, caption, CTA, and publish metadata
- review a storyboard or carousel sequence
- preserve external IDs for a pipeline apply step

Minimal shape:

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
        "briefId": "brief_abc",
        "platform": "tiktok",
        "hook": "The opening promise",
        "caption": "Caption text",
        "cta": "Follow for more",
        "videoPath": "out/video/final.mp4",
        "publicMediaUrl": "https://example.com/final.mp4"
      },
      "constraints": {
        "minSelected": 1,
        "maxSelected": 1,
        "requiresOrder": true,
        "requiredAspect": "9:16"
      },
      "items": [
        {
          "id": "frame_001",
          "path": "out/video/frames/frame-001.png",
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

For video groups, `videoPath` should point at a local file when available. SwipeSheet plays that video inline and treats the image items as preview frames, not separate posts.

## aut0gen Flow

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

Then aut0gen can apply the completed session with its own command:

```bash
npm run cli -- review:apply --session .swipesheet/sessions/latest.json
```

## Skill Or MCP?

Use the CLI by default. It is transparent, easy to inspect, and works from any repo.

Use a Codex skill when agents repeatedly need to create manifests, launch review sessions, and consume exports. This repository includes an optional template at `integrations/codex-skill/swipesheet/SKILL.md`.

Build an MCP server later only if the integration needs host-discoverable tool calls such as `create_review`, `wait_for_review`, `export_review`, and `list_sessions`. Today that adds complexity without replacing the native review window or the session JSON contract.

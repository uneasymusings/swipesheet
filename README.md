# SwipeSheet

[![CI](https://github.com/uneasymusings/swipesheet/actions/workflows/ci.yml/badge.svg)](https://github.com/uneasymusings/swipesheet/actions/workflows/ci.yml)

Contact sheets, but swipeable. Open a local folder or manifest, quickly approve/reject/annotate images in a native macOS window, then copy a clean export back into your AI CLI.

![SwipeSheet hero](docs/assets/hero.png)

## Why

Contact sheets are great for seeing everything at once, but they are painful when the next step is giving precise feedback to an AI agent. SwipeSheet turns that review pass into a focused desktop workflow:

- `x`: reject
- `y` or `Enter`: use this
- `m`: maybe / needs notes
- `n`: write feedback
- left/right arrows: navigate

At the end, **Finish and export** gives you copy-ready text with selected images, maybe items, rejection notes, and full original file paths.

![SwipeSheet demo](docs/assets/demo.gif)

## Built For

- Portfolio curation: review film scans, contact-sheet selects, or generated image folders and hand exact original paths back to a site-building agent.
- AI content review: approve persona candidates, feed images, thumbnails, and generated frames before they move into another pipeline step.
- Agent workflows: paste one structured export into Codex, Claude Code, or another CLI agent instead of manually describing image numbers.

## Features

- Native macOS AppKit review window.
- Zero runtime npm dependencies.
- Local-first: no uploads, no accounts, no database, no telemetry.
- Recursive folder scanning and manifest-based review.
- Plain JSON session files you can resume or inspect.
- Copy-ready AI-agent export plus JSON export for scripts.
- Works as a reusable CLI from any project directory.

## Quick Start

Requirements:

- macOS
- Node.js 18.18 or newer
- Xcode Command Line Tools / Swift compiler

Run the included sample:

```bash
npm test
npm run build:native
npm start
```

Review a real folder:

```bash
node ./bin/swipesheet.js review ~/Desktop/PHOTO --title "Portfolio scenic selects"
```

Review a manifest:

```bash
node ./bin/swipesheet.js review ./examples/sample-manifest.json \
  --title "Example review" \
  --prompt "Pick strong images and note any conditions before use."
```

## CLI

```bash
swipesheet review <image-or-folder-or-manifest...> [options]
swipesheet resume <session-json> [options]
swipesheet export <session-json> [--format agent|json]
swipesheet build-native
```

Review options:

```text
--title <text>          Human-readable review title
--prompt <text>         Review intent copied into the final export
--session <name>        Short name used in the session filename
--batch-size <number>   Number of images shown in the queue strip, default 20
--limit <number>        Review only the first N discovered images
```

Because this repo is not globally installed, run the local binary directly:

```bash
node ./bin/swipesheet.js review <sources...>
```

From another project:

```bash
node /Users/you/path/to/swipesheet/bin/swipesheet.js review ./out/images \
  --title "Approval pass"
```

## Inputs

SwipeSheet accepts:

- directories of images, scanned recursively
- direct image paths
- JSON manifests
- text, CSV, or TSV files containing image paths

Supported extensions:

```text
jpg jpeg png gif webp bmp svg avif heic heif tif tiff dng cr2 nef arw raf rw2
```

The native viewer asks macOS to load each image with `NSImage`, so common photo formats such as JPG, PNG, TIFF, HEIC, and GIF are handled directly. If macOS cannot display a file, the app still keeps the original path and shows a placeholder.

## Manifest Format

The simplest manifest is an array of paths:

```json
[
  "/absolute/path/to/image-01.jpg",
  "/absolute/path/to/image-02.jpg"
]
```

For richer workflows:

```json
{
  "images": [
    {
      "path": "out/mari/candidate-01.png",
      "label": "Mari",
      "note": "Generated identity candidate",
      "score": 8
    }
  ]
}
```

Relative paths resolve from the manifest file's directory. Extra fields are preserved in `metadata` and included in JSON exports.

## Sessions

Sessions are saved under the project where you run the command:

```text
.swipesheet/
  sessions/
    20260625T190000Z-review.json
  bin/
    swipesheet-macos
```

That makes it practical for other repos to invoke the tool. A portfolio repo can keep its own review history, while an AI content pipeline can keep approval sessions next to generated outputs.

## Export Example

The agent-oriented export looks like this:

```text
# Image review export: Portfolio film selects

Reviewed: 42/42
Use: 18
Maybe / needs notes: 4
Reject: 20

Selected images:
- #0001 | Roll 12 | frame-001.tif
   path: /Users/you/Desktop/PHOTO/Roll 12/frame-001.tif
   note: Use for homepage hero, crop tighter on the left.
```

Export later from the terminal:

```bash
node ./bin/swipesheet.js export .swipesheet/sessions/<session>.json
node ./bin/swipesheet.js export .swipesheet/sessions/<session>.json --format json
```

## Development

```bash
npm test
npm run build:native
npm run assets:demo
```

`npm run assets:demo` requires ImageMagick's `magick` binary and regenerates the README demo GIF from the generated sample images.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Workflow Guide](docs/WORKFLOWS.md)
- [Generated Assets](docs/ASSETS.md)
- [Roadmap](docs/ROADMAP.md)

## License

MIT

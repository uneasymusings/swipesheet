# Architecture

SwipeSheet is intentionally small. It should be easy to understand, easy to run from another project, and reliable with large folders of local assets.

## Components

```text
bin/swipesheet.js
  CLI entry point

src/cli.js
  Argument parsing, session creation, native app startup, terminal export

src/native.js
  On-demand Swift compilation and native app launch

src/lib/images.js
  Source discovery, recursive scanning, flat and grouped manifest parsing, de-duping

src/lib/session.js
  Session JSON creation, latest pointer, loading, mutation, progress summaries

src/lib/exporter.js
  Copy-ready agent export, generic JSON export, and grouped aut0gen JSON export

src/lib/autogen.js
  Helper manifest generation for aut0gen persona and content-set reviews

native/macos/ImagePickerApp.swift
  Native macOS AppKit review window
```

## Data Flow

1. A project runs `swipesheet review <sources...>`.
2. The CLI discovers image files or parses a flat/grouped manifest.
3. A session JSON file is created in `.swipesheet/sessions/` and `latest.json` points at it.
4. The CLI compiles `native/macos/ImagePickerApp.swift` into `.swipesheet/bin/swipesheet-macos` if needed.
5. The native macOS window opens with the session file path.
6. Item decisions, item notes, group decisions, group notes, and storyboard `itemOrder` changes are saved directly back to the session JSON.
7. The export is generated from the session in the app or with `swipesheet export`.

## Image Loading

The export must always point at the original file. The app uses macOS `NSImage` to display local images directly, so TIFF-heavy film workflows do not need a browser preview server.

If macOS cannot display an image, the app shows a placeholder but still preserves the path for export. A later version can add generated preview caching for RAW formats.

This is especially useful for film scan workflows where originals may be TIFF files.

## Local Boundary

There is no web server. The native app reads only the session JSON and the image paths already present in that session.

Session files do contain full local paths. They belong in `.swipesheet/`, which is ignored by git.

## Why Not Electron or Tauri?

The first version uses AppKit directly because the user experience should feel like a local utility, not a browser tab. It also keeps dependencies at zero.

- Node is used where it is strong: CLI ergonomics, manifest parsing, project integration.
- Swift/AppKit is used where it is strong: the native review window.
- The app can still grow into a packaged `.app` later without changing the session format.

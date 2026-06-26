# Roadmap

## Version 0.1

- Native macOS review window
- Keyboard-driven review UI
- Recursive folder scanning
- JSON/text/CSV/TSV manifests
- Grouped JSON review manifests
- Group-level decisions and notes
- Manifest-defined item and group actions
- Storyboard/slideshow strip with drag reorder
- Session persistence
- Agent-ready text export
- JSON export
- Aut0gen grouped JSON export
- Aut0gen persona/content-set manifest helpers

## Near-Term Improvements

- Add a `--group-by` option for persona, roll, folder, or manifest field.
- Add per-group quotas, such as "pick one per persona".
- Add a larger group compare grid for one content set at a time.
- Add quota warnings that understand `minSelected` and selected item counts.
- Add a command that copies approved images into an output folder.
- Add optional contact-sheet import helpers for numbered sheets.
- Add a compact "compare current 4" view for near-duplicates.
- Add undo history beyond manual navigation.
- Add preview caching for formats macOS cannot render directly.
- Add a first-run sample project with tiny generated placeholder images.

## Packaging Possibilities

The current app is a native desktop tool launched from the CLI. A future package could add:

- native file/folder picker
- drag-and-drop launch
- signed macOS distribution

The current CLI-first flow remains useful even after packaging because other projects can launch it programmatically.

## aut0gen Integration Ideas

- `aut0gen review:candidates` could write a manifest and launch this picker.
- The JSON export could update `persona.json` files directly.
- A staged content set could require a completed picker session before scheduling.
- Review notes could become training data for future prompt scoring.

## Portfolio Integration Ideas

- A photo cull script could pass existing deduped manifests into the picker.
- Approved originals could be copied into a site asset folder.
- Export notes could map directly to page sections, crop instructions, or alt text drafts.

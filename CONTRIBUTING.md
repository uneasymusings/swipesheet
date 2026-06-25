# Contributing

SwipeSheet is early, practical software. Contributions should keep the tool local-first, dependency-light, and easy to invoke from another project.

## Development

```bash
npm test
npm run build:native
npm start
```

`npm start` opens the sample review session. Real reviews use:

```bash
node ./bin/swipesheet.js review <image-folder-or-manifest>
```

## Guidelines

- Keep review data in plain JSON.
- Do not add cloud uploads or telemetry.
- Prefer small, focused modules over framework-heavy rewrites.
- Keep the CLI usable from any project directory.
- Update docs when changing the session format, CLI behavior, or export text.

## Demo Assets

The generated README/demo visuals live in `docs/assets/` and `examples/images/`. Regenerate the GIF with:

```bash
npm run assets:demo
```

That command requires ImageMagick's `magick` binary.

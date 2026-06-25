# Generated Assets

This repository includes AI-generated visual assets for the README and sample review session. They are illustrative project assets, not user data.

## Files

- `docs/assets/hero.png`: README hero image.
- `docs/assets/demo.gif`: short animated product demo.
- `docs/assets/demo-poster.png`: static poster frame for the demo.
- `examples/images/generated-scenic.png`: portfolio-style landscape sample.
- `examples/images/generated-persona.png`: fictional persona review sample.
- `examples/images/generated-still-life.png`: workflow still-life sample.

The demo GIF is reproducible from the sample images:

```bash
npm run assets:demo
```

## Generation Notes

The raster images were generated with Codex's built-in image generation tool on June 25, 2026, then copied into the workspace. The demo GIF was rendered locally with `scripts/render-demo-gif.js` and ImageMagick.

Prompts intentionally avoided logos, watermarks, real people, brand marks, and readable text. The fictional persona image is synthetic and is not intended to resemble a real person or public figure.

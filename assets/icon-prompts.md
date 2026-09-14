# Icon prompts

Created with the built-in image generation tool. The final PNG has a transparent
background. Packaging resizes the source for the macOS icon representations.

## Initial generation

```text
Use case: logo-brand
Asset type: final macOS application icon, square 1024 by 1024 PNG.
Primary request: Create an elegant, highly legible icon for Brave Container Setup, a small utility that routes web links into separate browser containers.
Subject: Three overlapping upright browser-window cards, aligned in a compact stack with just a small offset. A vivid warm orange front card dominates; behind it, visible tabs and edges in restrained violet and turquoise distinguish the containers. In the orange card, a single bold white chain-link symbol made of two interlocking rounded links. The icon must read clearly at 32 pixels.
Style: Polished native macOS app icon, sculpted satin materials, subtle depth and soft directional light, precise simple geometry, restrained highlights. Use a warm ivory rounded-square macOS tile behind the central symbol. Center the composition with balanced optical weight, front view, no dramatic perspective.
Composition: One icon only. Tile fills about 88 percent of the square canvas with generous consistent margins. Preserve a genuinely transparent background outside the rounded-square tile and its subtle soft shadow, with real alpha transparency, not a checkerboard drawing.
Constraints: No letters, words, captions, numerals, watermark, mockup, screenshots, additional icons, device frames, official Brave lion logo, security shields, padlocks, tiny UI controls, or fine detail. Keep silhouette and chain-link glyph bold, simple, and instantly readable. Deliver the finished icon artwork, not a presentation sheet.
```

## Edge cleanup

```text
Use case: precise-object-edit / background-extraction.
Edit target: the attached macOS app icon.
Make one targeted production cleanup: replace the ragged, speckled fringe around the OUTSIDE perimeter of the ivory rounded-square tile with a perfectly smooth, clean antialiased rounded-square silhouette and genuinely transparent alpha outside it. Remove every detached pixel, white speck, halo, and paint-like rough edge outside the tile. The transparent margins must be completely clean. A faint smooth drop shadow is allowed; no noisy shadow. Keep all interior artwork unchanged: same three orange, violet, teal browser cards, white chain link, colors, lighting, proportions and composition. No new elements, no words, no background plane. Output one square PNG app icon, ideally 1024x1024, with real alpha transparency.
```

This intermediate result had an opaque checkerboard. The final edit removed it.

## Final background extraction

```text
Remove the entire gray checkerboard background from this app icon. Return the ivory rounded-square tile and the orange, purple and teal cards on a genuinely TRANSPARENT background. This is background extraction only. Preserve every pixel of the icon inside the smooth rounded ivory tile. Outside that tile must have alpha 0; the PNG must have an alpha channel. Do not draw a checkerboard, white backdrop, gray backdrop, black backdrop, shadow or halo. Clean smooth antialiased edge on the tile. Preserve the same square canvas, scale and position. No other changes.
```

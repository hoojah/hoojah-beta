A Lucide glyph rendered inline with `currentColor` — the only icon system Hoojah uses.

```jsx
<Icon name="swords" size={16} />
<Icon name="thumbs-up" color="var(--color-agree)" />
<Icon name="flame" size={24} />
```

Sizes: 16px inline in cards/counts, 24px in the fixed navbar and sub-nav. Never emoji, never a PNG icon, never a hand-drawn SVG. `STANCE_ICON` maps agree/neutral/disagree to thumbs-up/minus/thumbs-down; `STANCE_COLOR` maps stance names to the CSS custom properties.
Requires the lucide UMD script on the page: `<script src="https://unpkg.com/lucide@0.469.0/dist/umd/lucide.js"></script>`.

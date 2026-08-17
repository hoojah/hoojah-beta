The circular stance vote button — 44px, 2px stance border, fills solid when it is the viewer's vote.

```jsx
<VoteButton stance="agree" voted onClick={vote} />
<VoteButton stance="neutral" />
```

Press feedback is `scale(0.95)` only; there is no ripple, spinner or fade. Glyphs are fixed: agree → thumbs-up, neutral → minus, disagree → thumbs-down.

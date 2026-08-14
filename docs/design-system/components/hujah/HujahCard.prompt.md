The primary unit of the product — one top-level hoojah with its vote widget.

```jsx
<HujahCard hujah={h} responseCount={4} userVote="agree" onVote={vote} onOpen={openHujah} />
<HujahCard hujah={h} size="detail" showShare responseCount={12} />
```

Feed cards stack with 8px gaps; body is 18px `leading-snug` (20px with `size="detail"`). The footer is always bar-chart-2 + total votes · message-circle + response count.

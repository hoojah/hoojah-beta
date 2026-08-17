A debate's entry in a hoojah's "Debates" lens, plus the two status primitives.

```jsx
<DebateCard challenger="tomkurus" opponent="mayaz" status="pending" onClick={open} />
<DebateStatus status="declined" opponent="mayaz" />
```

State colours are fixed: pending → agree orange, active → indigo, concluded → grey, declined → light-grey. The label is always 12px uppercase with wide tracking. The swords glyph is pink (`--color-neutral`).

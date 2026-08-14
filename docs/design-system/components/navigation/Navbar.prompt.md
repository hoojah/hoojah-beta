The fixed 56px top bar present on every signed-in screen.

```jsx
<Navbar user={{username:"mayaz", full_name:"Maya Zaharudin"}} unread={3} onNavigate={setScreen} />
<Navbar onNavigate={setScreen} />
```

`white/90` + `backdrop-blur` with a hairline bottom border — the only blur in the product. The brand is the bold indigo *text* lockup, not the SVG wordmark. Unread notifications show as an 8px pink (`--color-neutral`) dot, never a count badge.

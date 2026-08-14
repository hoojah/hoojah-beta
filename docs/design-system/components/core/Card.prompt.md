The white square-cornered `shadow` surface all Hoojah content sits on. Never round a feed card.

```jsx
<Card as="article">…</Card>
<Card stance="agree" padded>…</Card>
<Divider />
```

Cards stack with 8px gaps on a white page. Internal sections are separated by `<Divider />` (a #f3f4f6 hairline), not by extra shadow.

The trending list — a 256px lazy sidebar on wide feed viewports, and the whole `/trending` page.

```jsx
<TrendingList items={[{body:"…", username:"hoojah"}]} onOpen={open} />
```

All grey text, no cards, no numbers, no rank badges. Bodies truncate at ~90 characters. Empty copy is exactly "Nothing trending yet."

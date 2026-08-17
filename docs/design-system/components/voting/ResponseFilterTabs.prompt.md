The segmented control that filters a hoojah's threaded responses by stance.

```jsx
<ResponseFilterTabs value={filter} onChange={setFilter} />
```

Four equal cells inside one light-grey-bordered, `shadow`ed, 4px-rounded group: "All" + message-circle, then the three stance glyphs in their stance colors. It filters what is already on the page — it never refetches.

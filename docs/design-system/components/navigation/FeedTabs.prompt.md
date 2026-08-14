The feed's scope tabs — 14px medium, hairline rule underneath, active tab indigo with a 2px indigo underline.

```jsx
<FeedTabs value={scope} onChange={setScope} />
```

"Following" only exists for a signed-in viewer. These are real page-level scopes, not client filters — an empty Following feed reads "Your Following feed is empty. Follow some people to see their hoojahs here."

The follow/block pair on a profile header. Designed for the indigo background only.

```jsx
<FollowButton state="following" onToggle={unfollow} onBlock={block} />
<FollowButton state="requested" />
```

Rules from the app: if you blocked them the only control is Unblock; if they blocked you the only control is Block — Follow is never offered for a hidden pair. A private account turns Follow into "Requested" (clock glyph).

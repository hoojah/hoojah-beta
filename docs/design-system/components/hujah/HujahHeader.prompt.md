The byline block at the top of every hoojah card, plus the `ParentStub` shown above a reply.

```jsx
<HujahHeader user={hujah.user} date="Apr 16" right={<ShareMenu hujah={hujah} />} />
<ParentStub parent={hujah.parent} onClick={openParent} />
```

Full name is indigo medium; `@handle · date` is 14px grey underneath. Timestamps are always the compact "%b %-d" form.

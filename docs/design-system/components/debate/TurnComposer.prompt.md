The turn form at the foot of a debate transcript, with its two non-form states.

```jsx
<TurnComposer value={draft} onChange={setDraft} onSubmit={post} />
<TurnComposer state="waiting" waitingFor="mayaz" />
<TurnComposer state="concluded" />
```

Placeholder is exactly "Make your argument…"; the submit pill reads "Post turn" and is right-aligned.

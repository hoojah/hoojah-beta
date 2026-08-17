The compact stance-bordered card used for threaded responses and for a user's hoojahs on their profile.

```jsx
<CompactHujahCard hujah={child} stance="agree" onClick={open} />
<ChallengeLink onClick={openChallengeDialog} />
```

The 8px left border is the responder's stance — this is the signature Hoojah motif. Tallies below the body are faint light-grey, all three stances always shown. `ChallengeLink` renders below the card (never inside it) and only for a signed-in viewer who is not the author.

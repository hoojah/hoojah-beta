The vote widget that sits inside every hoojah card and the single-hoojah screen — three rows of button + 8px track + percentage.

```jsx
<VoteBars counts={{agree: 42, neutral: 9, disagree: 17}} userVote="agree" onVote={setVote} />
<VoteBars counts={dist} readOnly labels />
```

Percentages are rounded whole numbers of the three-stance total; with zero votes every bar reads 0%. The read-only form is what the dashboard's per-hoojah distribution uses.

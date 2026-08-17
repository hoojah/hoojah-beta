The spectator verdict block, only ever on a *concluded* debate.

```jsx
<Verdict challenger="tomkurus" opponent="mayaz" canVote onVote={vote} />
<Verdict challenger="tomkurus" opponent="mayaz" tally={{challenger:12,opponent:7,draw:2}} />
```

Colours: challenger indigo, opponent purple, draw grey. Participants, anonymous viewers and anyone who already voted see the read-only bars; with no votes it reads "No verdicts yet."

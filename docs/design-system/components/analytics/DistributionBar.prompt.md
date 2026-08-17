One hoojah's vote split on the dashboard — read-only bars, no buttons.

```jsx
<DistributionBar body={h.body} counts={{agree:42,neutral:9,disagree:17}} />
<DistributionBar body={h.body} counts={{agree:2,neutral:1,disagree:0}} />
```

Under 5 total votes the numbers are withheld and it reads "fewer than 5 votes" — a privacy floor, keep it.

The product's only overlay: an 8px-rounded `shadow-lg` panel on a black/40 backdrop, max 448px wide, with a hairline header (title + X).

```jsx
<Dialog open={open} title="Flag this hoojah" onClose={close}>
  <div style={{padding:"var(--space-4)"}}>
    <p style={{fontSize:"var(--text-sm)",color:"var(--text-muted)"}}>Why are you flagging this hoojah?</p>
    <DialogChoiceList options={[{value:"spam",label:"It's suspicious or spam"}]} onPick={flag} />
  </div>
</Dialog>
```

Used for: Flag this hoojah, Challenge @user to a debate, Edit your profile. Rows hover to `--color-gray-50`; the footer action is right-aligned with a bare grey "Cancel".

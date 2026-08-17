The Hoojah button — a pill with a 2px colored border, white fill and colored text; `active:scale-95` on press.

```jsx
<Button icon="message-square-plus">Add hoojah</Button>
<Button tone="agree" icon="message-square-plus">Add hoojah</Button>
<Button variant="solid">Save changes</Button>
<Button variant="rect">Log in</Button>
<Button variant="onPrimary" icon="user-check">Following</Button>
```

Use `tone` to inherit the viewer's stance (the "Add hoojah" CTA on a hoojah you voted on takes that stance's color). `onPrimary`/`onPrimaryOutline` are only for use inside the blue profile header.

The white `shadow`ed 4px-rounded dropdown used for the avatar menu, the share menu and the more-actions menu.

```jsx
<DropdownMenu trigger={<Icon name="more-horizontal" size={24} />}>
  <MenuHeading>Share this hoojah via</MenuHeading>
  <MenuItem onClick={share}>WhatsApp</MenuItem>
  <MenuSeparator />
  <MenuItem tone="neutral" icon={<Icon name="flag" />}>Flag this hoojah</MenuItem>
</DropdownMenu>
```

Rows hover to `--color-gray-100`. A tiny 12px grey `MenuHeading` labels the menu; destructive/report rows take `tone="neutral"` (pink).

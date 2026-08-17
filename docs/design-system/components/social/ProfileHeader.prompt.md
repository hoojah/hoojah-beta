The full-bleed indigo profile block — the one saturated colour field in the product.

```jsx
<ProfileHeader user={u} badges={[BADGES.first_hoojah]} counts={{votes:128,hujahs:14,followers:39,following:52}} followState="follow" />
<ProfileHeader user={u} owner onEdit={openEditor} counts={{...}} />
<ProfileHeader user={u} gated followState="requested" counts={{followers:39,following:52}} />
```

Everything on it is white — text, icons, links (underlined). `gated` is the private-account view: avatar, name, handle, lock note, follow control and follower/following counts only; no headline, location, link, badges or hoojah list.

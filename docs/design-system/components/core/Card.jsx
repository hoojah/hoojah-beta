import React from "react";
import { STANCE_COLOR } from "./Icon";

/** The white, SQUARE-cornered, `shadow` surface every feed row sits on. `stance` adds the 8px colored left border of a compact card. */
export function Card({ stance, padded = false, as = "div", children, style, ...rest }) {
  const Tag = as;
  return (
    <Tag
      style={{
        background: "var(--surface-card)",
        boxShadow: "var(--shadow)",
        borderRadius: "var(--radius-none)",
        borderLeft: stance ? `var(--border-stance) solid ${STANCE_COLOR[stance] || stance}` : undefined,
        padding: padded ? "var(--space-3) var(--space-4)" : undefined,
        color: "var(--text-body)",
        textDecoration: "none",
        display: "block",
        ...style,
      }}
      {...rest}
    >
      {children}
    </Tag>
  );
}

/** Hairline rule used inside cards and menus. */
export function Divider({ style }) {
  return <div style={{ height: 1, background: "var(--border-hairline)", ...style }} />;
}

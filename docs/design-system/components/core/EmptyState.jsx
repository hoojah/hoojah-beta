import React from "react";
import { Icon } from "./Icon";

/** The product's one-line empty state: faint grey, a single Lucide glyph, a plain friendly sentence. */
export function EmptyState({ icon = "message-circle", children, tone = "faint", align = "left", style }) {
  const color = tone === "muted" ? "var(--text-muted)" : "var(--text-faint)";
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: align === "center" ? "center" : "flex-start",
        gap: "var(--space-1)",
        fontSize: "var(--text-sm)",
        color,
        background: "var(--surface-card)",
        padding: "var(--space-3)",
        ...style,
      }}
    >
      {icon ? <Icon name={icon} size={16} /> : null}
      <span>{children}</span>
    </div>
  );
}

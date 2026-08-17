import React from "react";
import { Icon, STANCE_COLOR } from "./Icon";

/**
 * Hoojah's button. The house style is a PILL with a 2px colored border, white fill and
 * colored text (`outline`). `solid` is the primary submit; `rect` is the squarer auth /
 * signup CTA; `link` is a bare text/icon control.
 */
export function Button({
  variant = "outline",
  tone = "primary",
  size = "md",
  icon,
  iconSize,
  children,
  as = "button",
  style,
  ...rest
}) {
  const color = STANCE_COLOR[tone] || tone;
  const pad = size === "sm" ? "4px 16px" : "8px 20px";
  const base = {
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    gap: "var(--space-1)",
    fontFamily: "inherit",
    fontSize: size === "sm" ? "var(--text-sm)" : "var(--text-base)",
    lineHeight: 1.25,
    cursor: "pointer",
    textDecoration: "none",
    transition: "transform 150ms, background-color 150ms, color 150ms",
    boxSizing: "border-box",
  };
  const variants = {
    outline: {
      padding: pad,
      borderRadius: "var(--radius-full)",
      border: `var(--border-pill) solid ${color}`,
      background: "var(--surface-card)",
      color,
      boxShadow: "var(--shadow)",
    },
    solid: {
      padding: pad,
      borderRadius: "var(--radius-full)",
      border: 0,
      background: color,
      color: "var(--text-inverse)",
      boxShadow: "var(--shadow)",
    },
    rect: {
      padding: pad,
      borderRadius: "var(--radius)",
      border: 0,
      background: color,
      color: "var(--text-inverse)",
    },
    onPrimary: {
      padding: "4px 16px",
      borderRadius: "var(--radius-full)",
      border: 0,
      background: "var(--color-white)",
      color: "var(--color-primary)",
      fontSize: "var(--text-sm)",
    },
    onPrimaryOutline: {
      padding: "4px 16px",
      borderRadius: "var(--radius-full)",
      border: "1px solid var(--color-white)",
      background: "transparent",
      color: "var(--color-white)",
      fontSize: "var(--text-sm)",
    },
    link: { padding: 0, border: 0, background: "transparent", color },
  };
  const Tag = as;
  return (
    <Tag
      style={{ ...base, ...(variants[variant] || variants.outline), ...(rest.disabled ? { opacity: 0.5, cursor: "default" } : null), ...style }}
      onMouseDown={(e) => { e.currentTarget.style.transform = "scale(0.95)"; }}
      onMouseUp={(e) => { e.currentTarget.style.transform = "none"; }}
      onMouseLeave={(e) => { e.currentTarget.style.transform = "none"; }}
      {...rest}
    >
      {icon ? <Icon name={icon} size={iconSize || (size === "sm" ? 14 : 16)} /> : null}
      {children}
    </Tag>
  );
}

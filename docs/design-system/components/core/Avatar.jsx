import React from "react";

const initials = (name = "") =>
  name.trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join("").toUpperCase() || "?";

/** Round user photo. Production photos come from Cloudinary; without one we fall back to initials on primary. */
export function Avatar({ src, name = "", size = 44, style, ...rest }) {
  const base = {
    width: size,
    height: size,
    borderRadius: "var(--radius-full)",
    flexShrink: 0,
    objectFit: "cover",
    display: "block",
    ...style,
  };
  if (src) return <img src={src} alt={name} style={base} {...rest} />;
  return (
    <span
      aria-label={name}
      style={{
        ...base,
        background: "var(--color-primary)",
        color: "var(--text-inverse)",
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        fontSize: Math.round(size * 0.38),
        fontWeight: "var(--font-medium)",
        letterSpacing: "0.02em",
      }}
      {...rest}
    >
      {initials(name)}
    </span>
  );
}

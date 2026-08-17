import React from "react";

const pascal = (n) => String(n).split(/[-_ ]/).filter(Boolean).map((s) => s[0].toUpperCase() + s.slice(1)).join("");

/** Lucide glyph. Hoojah uses Lucide exclusively (the Rails app via lucide-rails; here via the lucide UMD CDN). */
export function Icon({ name, size = 16, strokeWidth = 2, color, className, style, ...rest }) {
  const L = typeof window !== "undefined" ? window.lucide : null;
  const key = pascal(name);
  const node = L ? (L.icons && L.icons[key]) || L[key] : null;
  // A lucide icon node is ["svg", attrs, children]; older shapes are just the children array.
  const kids = Array.isArray(node) ? (Array.isArray(node[2]) ? node[2] : Array.isArray(node[0]) ? node : null) : null;
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
      style={{ display: "inline-block", flexShrink: 0, verticalAlign: "middle", color, ...style }}
      {...rest}
    >
      {kids ? kids.map(([tag, attrs], i) => React.createElement(tag, { key: i, ...attrs })) : null}
    </svg>
  );
}

/** stance name -> Lucide glyph, per app/helpers/icons_helper.rb */
export const STANCE_ICON = { agree: "thumbs-up", neutral: "minus", disagree: "thumbs-down" };
/** stance name -> CSS custom property */
export const STANCE_COLOR = {
  agree: "var(--color-agree)",
  neutral: "var(--color-neutral)",
  disagree: "var(--color-disagree)",
  primary: "var(--color-primary)",
  grey: "var(--color-grey)",
  "light-grey": "var(--color-light-grey)",
};

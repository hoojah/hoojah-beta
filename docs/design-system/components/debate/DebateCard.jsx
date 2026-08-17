import React from "react";
import { Card } from "../core/Card";
import { Icon, STANCE_COLOR } from "../core/Icon";

export const DEBATE_STATE_COLOR = { pending: "var(--color-agree)", active: "var(--color-primary)", concluded: "var(--color-grey)", declined: "var(--color-light-grey)" };

/** A debate's row in a hoojah's Debates lens: swords glyph, "@a vs @b", and the uppercase state label. */
export function DebateCard({ challenger, opponent, status = "active", onClick, style }) {
  return (
    <Card
      as="a"
      href="#"
      onClick={(e) => { e.preventDefault(); if (onClick) onClick(); }}
      style={{ padding: "var(--space-2) var(--space-4)", display: "flex", alignItems: "center", justifyContent: "space-between", ...style }}
    >
      <span style={{ display: "flex", alignItems: "center", gap: "var(--space-1)", color: "var(--text-body)", minWidth: 0 }}>
        <span style={{ color: STANCE_COLOR.neutral, display: "flex" }}><Icon name="swords" size={16} /></span>
        <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>@{challenger} vs @{opponent}</span>
      </span>
      <DebateStateLabel status={status} />
    </Card>
  );
}

/** The uppercase, tracked, state-coloured status word. */
export function DebateStateLabel({ status = "active", style }) {
  return (
    <span style={{ flexShrink: 0, marginLeft: "var(--space-2)", fontSize: "var(--text-xs)", textTransform: "uppercase", letterSpacing: "var(--tracking-wide)", color: DEBATE_STATE_COLOR[status] || "var(--color-grey)", ...style }}>
      {status[0].toUpperCase() + status.slice(1)}
    </span>
  );
}

/** The status block on the transcript screen — state label plus the declined note. */
export function DebateStatus({ status = "active", opponent, style }) {
  return (
    <span style={{ display: "flex", flexDirection: "column", minWidth: 0, ...style }}>
      <DebateStateLabel status={status} style={{ marginLeft: 0 }} />
      {status === "declined" ? <span style={{ fontSize: "var(--text-sm)", color: "var(--text-muted)" }}>@{opponent} declined the challenge.</span> : null}
    </span>
  );
}

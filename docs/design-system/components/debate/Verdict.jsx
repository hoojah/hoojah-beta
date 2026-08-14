import React from "react";
import { Card } from "../core/Card";
import { Button } from "../core/Button";

const COLORS = { challenger: "var(--color-primary)", opponent: "var(--color-disagree)", draw: "var(--color-grey)" };

/** The spectator verdict on a concluded debate — three vote pills for an eligible spectator, or the read-only tally. */
export function Verdict({ challenger, opponent, tally = {}, canVote = false, onVote, style }) {
  const rows = [
    ["challenger", "@" + challenger],
    ["opponent", "@" + opponent],
    ["draw", "Draw"],
  ];
  const total = rows.reduce((s, [k]) => s + (tally[k] || 0), 0);
  return (
    <Card style={{ padding: "var(--space-4)", margin: "var(--space-4) 0", ...style }}>
      <h2 style={{ fontSize: "var(--text-sm)", textTransform: "uppercase", letterSpacing: "var(--tracking-wide)", color: "var(--text-muted)", marginTop: 0, marginBottom: "var(--space-3)", fontWeight: "var(--font-medium)" }}>Spectator verdict</h2>
      {canVote ? (
        <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-2)" }}>
          {rows.map(([k, label]) => (
            <Button key={k} tone={k === "challenger" ? "primary" : k === "opponent" ? "disagree" : "grey"} onClick={() => onVote && onVote(k)}>{label}</Button>
          ))}
        </div>
      ) : (
        <>
          {rows.map(([k, label], i) => {
            const pct = total ? Math.round(((tally[k] || 0) * 100) / total) : 0;
            return (
              <div key={k} style={{ display: "flex", alignItems: "center", marginBottom: i === rows.length - 1 ? 0 : "var(--space-3)" }}>
                <small style={{ width: 112, flexShrink: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", color: COLORS[k], fontSize: "var(--text-sm)" }}>{label}</small>
                <div style={{ flex: 1, margin: "0 var(--space-3)", height: "var(--bar-h)", background: "var(--track-bar)", borderRadius: "var(--radius)", overflow: "hidden" }}>
                  <div style={{ height: "var(--bar-h)", borderRadius: "var(--radius)", background: COLORS[k], width: pct + "%" }} />
                </div>
                <small style={{ width: 40, textAlign: "right", color: COLORS[k], fontSize: "var(--text-sm)" }}>{pct}%</small>
              </div>
            );
          })}
          {!total ? <p style={{ color: "var(--text-muted)", textAlign: "center", fontSize: "var(--text-sm)", padding: "var(--space-1) 0", margin: 0 }}>No verdicts yet.</p> : null}
        </>
      )}
    </Card>
  );
}

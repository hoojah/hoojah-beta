import React from "react";
import { Card } from "../core/Card";
import { Button } from "../core/Button";
import { TextAreaField } from "../forms/TextAreaField";

/** The debate turn form — shown only to the participant whose turn it is; everyone else gets the waiting / concluded note. */
export function TurnComposer({ state = "yours", waitingFor, value, onChange, onSubmit, style }) {
  if (state === "waiting") return <p style={{ color: "var(--text-muted)", textAlign: "center", padding: "var(--space-3) 0", ...style }}>Waiting for @{waitingFor}…</p>;
  if (state === "concluded") return <p style={{ color: "var(--text-muted)", textAlign: "center", padding: "var(--space-3) 0", ...style }}>This debate has concluded.</p>;
  return (
    <Card style={{ padding: "var(--space-4)", ...style }}>
      <TextAreaField rows={3} placeholder="Make your argument…" aria-label="Your turn" value={value} onChange={onChange} style={{ marginBottom: 0 }} />
      <div style={{ textAlign: "right", marginTop: "var(--space-2)" }}>
        <Button onClick={onSubmit}>Post turn</Button>
      </div>
    </Card>
  );
}

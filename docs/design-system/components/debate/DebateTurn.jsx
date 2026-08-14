import React from "react";
import { Card } from "../core/Card";
import { Avatar } from "../core/Avatar";

/** One turn in a debate transcript: 32px avatar byline over the argument body. */
export function DebateTurn({ user = {}, date, body, style }) {
  return (
    <Card padded style={{ ...style }}>
      <div style={{ display: "flex", alignItems: "center", minWidth: 0, marginBottom: "var(--space-1)" }}>
        <Avatar src={user.photo} name={user.full_name} size={32} style={{ marginRight: "var(--space-2)" }} />
        <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
          <span style={{ color: "var(--color-primary)", fontWeight: "var(--font-medium)" }}>{user.full_name}</span>
          <small style={{ color: "var(--text-muted)", fontSize: "var(--text-sm)" }}>
            @{user.username}{date ? <><span style={{ margin: "0 var(--space-1)" }}>·</span>{date}</> : null}
          </small>
        </div>
      </div>
      <div style={{ color: "var(--text-body)", overflowWrap: "break-word" }}>{body}</div>
    </Card>
  );
}

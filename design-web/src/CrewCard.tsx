import React from "react";
import { AvatarChip } from "./AvatarChip";
import { KLabel } from "./KLabel";
import { ExtrudedButton } from "./ExtrudedButton";

export interface CrewMember {
  /** Two-letter initials. */
  initials: string;
  /** The member's lifter color. */
  color: string;
  /** Burpees owed to the crew; 0/undefined renders the green good-standing check. */
  owes?: number;
  /** Training right now — renders the pulsing accent presence ring + LIFTING NOW. */
  active?: boolean;
}

export interface CrewCardProps {
  /** The crew, in display order. */
  members: CrewMember[];
  /** Next routine on the docket. */
  routineName: string;
  /** When it happens (e.g. "FRI 5:30"). */
  routineTime: string;
  /** How many members confirmed for the next routine — renders "N IN" on the button. */
  routineConfirmed?: number;
  /** Tapping the routine button opens the routine preview. */
  onRoutineTap?: () => void;
  /** Tapping the card body opens the blackboard sheet (debts + bookings detail). */
  onCardTap?: () => void;
  style?: React.CSSProperties;
}

/**
 * The crew card: every member with their burpee standing (green check = square with
 * the crew, gold count = owed), and the next routine as an extruded button. Debts are
 * owed to the crew, never to individuals. The whole card is tappable (blackboard sheet).
 */
export function CrewCard({ members, routineName, routineTime, routineConfirmed, onRoutineTap, onCardTap, style }: CrewCardProps) {
  return (
    <div className="ox-card" style={{ cursor: onCardTap ? "pointer" : undefined, ...style }} onClick={onCardTap}>
      <div style={{ display: "flex", justifyContent: "space-around" }}>
        {members.map((m) => (
          <div key={m.initials} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
            <span className={m.active ? "ox-presence" : undefined}>
              <AvatarChip initials={m.initials} color={m.color} />
            </span>
            {m.active ? (
              <KLabel tone="accent">LIFTING NOW</KLabel>
            ) : m.owes ? (
              <KLabel tone="gold">{m.owes}</KLabel>
            ) : (
              <KLabel tone="green">✓</KLabel>
            )}
          </div>
        ))}
      </div>
      <ExtrudedButton
        wide
        style={{ marginTop: 13, padding: "11px 12px" }}
        onClick={onRoutineTap}
      >
        <span style={{ fontSize: 12.5, fontWeight: 800, whiteSpace: "nowrap" }}>▸ {routineName}</span>
        <span style={{ display: "inline-flex", gap: 8, alignItems: "center", whiteSpace: "nowrap" }}>
          {routineConfirmed !== undefined && <KLabel tone="accent">{routineConfirmed} IN</KLabel>}
          <KLabel style={{ color: "var(--onyx-n700)" }}>{routineTime} ›</KLabel>
        </span>
      </ExtrudedButton>
    </div>
  );
}

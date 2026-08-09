import React from "react";
import { AvatarChip } from "./AvatarChip";
import { KLabel } from "./KLabel";

export interface BubbleProps {
  /** `in` = crew member (grey, left); `out` = the user (accent, right, dark ink). */
  direction: "in" | "out";
  /** Draw the iMessage tail — only on the last bubble of a sender's run. */
  tail?: boolean;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}

/**
 * An iMessage-grammar chat bubble in Onyx colors: 19px radius, tails on the last
 * bubble of a run, accent-with-dark-ink for outgoing instead of Apple blue.
 */
export function Bubble({ direction, tail = false, children, style }: BubbleProps) {
  const cls = [
    "ox-bubble",
    direction === "in" ? "ox-bubble--in" : "ox-bubble--out",
    tail && "ox-bubble--tail",
  ]
    .filter(Boolean)
    .join(" ");
  return (
    <div className={cls} style={style}>
      {children}
    </div>
  );
}

export interface MsgRowProps {
  /** `me` right-aligns the row for outgoing bubbles. */
  me?: boolean;
  /** Ends a sender's run (adds the group gap below). */
  endOfRun?: boolean;
  /** Avatar initials+color for incoming rows — shown only on the last row of a run. */
  avatar?: { initials: string; color?: string };
  children?: React.ReactNode;
}

/**
 * A chat message row: bubble alignment, run spacing, and the incoming avatar slot.
 * Compose consecutive rows from one sender with `endOfRun` on the last.
 */
export function MsgRow({ me = false, endOfRun = false, avatar, children }: MsgRowProps) {
  const cls = ["ox-msgrow", me && "ox-msgrow--me", endOfRun && "ox-msgrow--grp"].filter(Boolean).join(" ");
  return (
    <div className={cls}>
      {!me && (avatar ? <AvatarChip initials={avatar.initials} color={avatar.color ?? "#3a3f46"} size={28} /> : <span style={{ width: 28 }} />)}
      {children}
    </div>
  );
}

export interface SysLineProps {
  /** The member's lifter color — renders their mini plate glyph. */
  color: string;
  /** Event text (e.g. "DANI PUT A PLATE ON THE BAR · PULL DAY B"). */
  text: string;
  /** Cheer count; renders the extruded cheer chip when present. */
  cheers?: number;
}

/**
 * A session system-line inside the chat: a completed workout surfaces in the stream
 * as a mini plate glyph + event text, cheerable inline. Sessions are chat citizens.
 */
export function SysLine({ color, text, cheers }: SysLineProps) {
  return (
    <div className="ox-sysline">
      <span className="ox-sysline__plate" style={{ background: color }} />
      <KLabel style={{ color: "var(--onyx-t78)" }}>{text}</KLabel>
      {cheers !== undefined && (
        <button type="button" className="ox-btn ox-btn--sm" style={{ padding: "4px 8px", fontSize: 9, color: "var(--onyx-ac)" }}>
          💪 {cheers}
        </button>
      )}
    </div>
  );
}

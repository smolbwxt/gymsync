import React from "react";

export interface CrewChipProps {
  /** Short crew tag shown in the chip (e.g. "IC" for Iron Church). */
  label: string;
  /** Crew color. */
  color: string;
  /** The currently-open crew gets the accent ring (over the lip — extrusion stays). */
  active?: boolean;
  /** Unread activity dot. */
  notify?: boolean;
  onClick?: () => void;
}

/**
 * Header crew selector chip — one per crew the user belongs to, extruded like all tappables.
 * The active crew carries the accent ring; others may carry an unread dot.
 */
export function CrewChip({ label, color, active = false, notify = false, onClick }: CrewChipProps) {
  return (
    <button
      type="button"
      className={active ? "ox-crewchip ox-crewchip--active" : "ox-crewchip"}
      style={{ background: color }}
      onClick={onClick}
    >
      {label}
      {notify && <span className="ox-crewchip__dot" />}
    </button>
  );
}

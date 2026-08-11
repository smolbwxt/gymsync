import React from "react";
import { KLabel } from "./KLabel";

export interface WeeksBarProps {
  /** Routines declared for the week (the commitment) — sets the slot count. */
  declared: number;
  /** Routines the crew completed **together** this week (crew-size invariant); one iron plate each. */
  completed: number;
  /** Rendered width in px. Default 370. */
  width?: number;
}

const PLATE_W = 20;
const COLLAR_X = 6;
const PLATE_X0 = COLLAR_X + 10; // plates load flush against the collar
const BAND_H = 90;
const SLEEVE_END = 185;

/**
 * The week's bar: one uniform iron plate per routine the crew completed together,
 * loading flush from the collar along a bare sleeve — bare steel is the work
 * remaining (no ghost plates, no clip). The skewed week count sits dead-center
 * above THIS WEEK, with a vertical slot column beside it — one slot per declared
 * routine, filled bottom-up, the next slot breathing. Ironclad (completed ≥
 * declared): green count and slots, no pulse. Plates are the crew's, never one
 * person's — who-showed detail lives one tap deep.
 */
export function WeeksBar({ declared, completed, width = 370 }: WeeksBarProps) {
  const done = Math.min(completed, declared);
  const ironclad = declared > 0 && completed >= declared;
  const midY = BAND_H / 2;

  return (
    <div className={ironclad ? "ox-bar ox-bar--ironclad" : "ox-bar"} style={{ width, height: BAND_H }}>
      {/* sleeve, trimmed short of the counter */}
      <div className="ox-bar__sleeve" style={{ left: 0, width: SLEEVE_END, top: midY - 5 }} />
      {/* collar — the fixed retainer; first plate sits flush */}
      <span className="ox-collar" style={{ left: COLLAR_X, top: midY - 13 }} />
      {/* the crew's iron, packed flush */}
      {Array.from({ length: done }, (_, i) => (
        <span key={i} className="ox-plate" style={{ left: PLATE_X0 + i * PLATE_W, top: midY - 37 }} />
      ))}
      {/* counter block + slot column at the sleeve's end */}
      <div style={{ position: "absolute", right: 0, top: 0, height: BAND_H, display: "flex", alignItems: "center", gap: 12 }}>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 4 }}>
          <span className="ox-bar__count">{completed}</span>
          <KLabel tone={ironclad ? "green" : "default"} style={{ letterSpacing: "1.8px", fontSize: 9, color: ironclad ? undefined : "var(--onyx-tx)", textAlign: "center" }}>
            THIS WEEK
          </KLabel>
        </div>
        <div style={{ display: "flex", flexDirection: "column-reverse", gap: 4 }}>
          {Array.from({ length: declared }, (_, i) => {
            const filled = i < done;
            const next = !filled && i === done && !ironclad;
            const cls = ["ox-bar__slot", filled && "ox-bar__slot--filled", next && "ox-bar__slot--next"]
              .filter(Boolean)
              .join(" ");
            return <span key={i} className={cls} />;
          })}
        </div>
      </div>
    </div>
  );
}

export interface CollarProps {
  /** Absolute x within an ox-bar (internal use); omit for inline display. */
  x?: number;
  /** Vertical top within an ox-bar band (internal use). */
  top?: number;
}

/**
 * The bar collar — the fixed retainer the crew's plates load flush against.
 */
export function Collar({ x, top }: CollarProps) {
  const style: React.CSSProperties =
    x === undefined ? { position: "relative", display: "inline-block" } : { left: x, top };
  return <span className="ox-collar" style={style} />;
}

export interface PlateProps {
  /** Height in px (width keeps the 20:74 iron aspect). Default 74. */
  height?: number;
}

/**
 * The plate: the crew's unit of shared effort — one plate is one routine the crew
 * completed together. Always uniform iron; never one member's, never colored by
 * identity. Lifter colors belong to avatars, not iron.
 */
export function Plate({ height = 74 }: PlateProps) {
  const w = (20 / 74) * height;
  return (
    <span
      style={{
        position: "relative", display: "inline-block", width: w, height,
        borderRadius: 3, background: "#53585F",
        boxShadow:
          "inset 1.5px 0 0 rgba(255,255,255,.20), inset -2px 0 0 rgba(0,0,0,.38), inset 0 2px 0 rgba(255,255,255,.09), inset 0 -2px 0 rgba(0,0,0,.30)",
      }}
    />
  );
}

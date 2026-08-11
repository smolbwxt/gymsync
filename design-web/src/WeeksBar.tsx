import React from "react";
import { KLabel } from "./KLabel";

export interface WeeksBarProps {
  /** Routines declared for the week (the Monday commitment) — sets where the clip clamps and the slot count. */
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

/**
 * The week's bar (v7.4): one uniform iron plate per routine the crew completed
 * together, loading flush from the collar toward a clip clamped at the declared
 * goal — bare sleeve to the clip is the work remaining (deliberately no ghost
 * plates). A skewed week count with a vertical slot column carries the numbers;
 * the next empty slot breathes. Ironclad (completed ≥ declared): gold clip, green
 * count and slots, no pulse. Who-showed detail lives one tap deep, never on the bar.
 */
export function WeeksBar({ declared, completed, width = 370 }: WeeksBarProps) {
  const done = Math.min(completed, declared);
  const ironclad = declared > 0 && completed >= declared;
  const clipX = PLATE_X0 + declared * PLATE_W + 2;
  const sleeveEnd = Math.max(clipX + 24, 185);
  const midY = BAND_H / 2;

  return (
    <div className={ironclad ? "ox-bar ox-bar--ironclad" : "ox-bar"} style={{ width, height: BAND_H }}>
      {/* sleeve, trimmed short of the counter */}
      <div className="ox-bar__sleeve" style={{ left: 0, width: sleeveEnd, top: midY - 5 }} />
      {/* collar — inboard, fixed; first plate sits flush */}
      <span className="ox-collar" style={{ left: COLLAR_X, top: midY - 13 }} />
      {/* iron plates, packed flush */}
      {Array.from({ length: done }, (_, i) => (
        <span key={i} className="ox-plate" style={{ left: PLATE_X0 + i * PLATE_W, top: midY - 37 }} />
      ))}
      {/* clip — outboard, clamped at the declared position in every phase */}
      <span className="ox-clip" style={{ left: clipX, top: midY - 21 }} />
      {/* counter block + slot column at the sleeve's end */}
      <div style={{ position: "absolute", right: 0, top: 0, height: BAND_H, display: "flex", alignItems: "center", gap: 12 }}>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 4 }}>
          <span className="ox-bar__count">{completed}</span>
          <KLabel tone={ironclad ? "green" : "default"} style={{ letterSpacing: "1.8px", fontSize: 9, color: ironclad ? undefined : "var(--onyx-tx)" }}>
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
 * The bar collar — the inboard, fixed retainer the shoulder plates load against.
 * (The removable retainer that bounds the load is the Clip.)
 */
export function Collar({ x, top }: CollarProps) {
  const style: React.CSSProperties =
    x === undefined ? { position: "relative", display: "inline-block" } : { left: x, top };
  return <span className="ox-collar" style={style} />;
}

export interface ClipProps {
  /** Absolute x within an ox-bar (internal use); omit for inline display. */
  x?: number;
  /** Vertical top within an ox-bar band (internal use). */
  top?: number;
  /** Gold treatment for the ironclad state. */
  gold?: boolean;
}

/**
 * The bar clip — the outboard, removable retainer that bounds the load. On the
 * week's bar it clamps at the declared goal and turns gold when the week is made.
 */
export function Clip({ x, top, gold = false }: ClipProps) {
  const style: React.CSSProperties = {
    ...(x === undefined ? { position: "relative", display: "inline-block" } : { left: x, top }),
    ...(gold ? { background: "var(--onyx-gold)" } : {}),
  };
  return <span className="ox-clip" style={style} />;
}

export interface PlateProps {
  /** Lifter color fill. */
  color: string;
  /** Height in px (width scales with it). Default 58. */
  height?: number;
}

/**
 * A lifter chip in plate form — a member-colored glyph used in system-lines,
 * cheer chips, and legends. NOT the barbell plate: the week's bar and GSBarLoader
 * draw their own iron (see upstream decision #9).
 */
export function Plate({ color, height = 58 }: PlateProps) {
  const w = (15 / 58) * height;
  return (
    <span
      style={{
        position: "relative", display: "inline-block", width: w, height,
        borderRadius: 3, background: color,
        boxShadow: "0 6px 9px -6px rgba(0,0,0,.72)",
      }}
    />
  );
}

import React from "react";

export interface WeeksBarSession {
  /** The lifter's dedicated color (see the Onyx lifter tokens). */
  color: string;
  /** Optional member tag for tooling/a11y. */
  member?: string;
}

export interface WeeksBarProps {
  /** Sessions the crew declared for the week — sets where the collars clamp. Render capacity is 8 (4 per sleeve); the count label carries any overflow. */
  declared: number;
  /** Completed sessions in order; each renders one plate in the lifter's color. */
  sessions: WeeksBarSession[];
  /** Faint marks on the bare sleeve where remaining plates will land. Default true. */
  showTicks?: boolean;
  /** Rendered width in px (design width 370, scaled proportionally). */
  width?: number;
}

const DESIGN_W = 370;
const SLOT = 17;
const PLATE_W = 15;
const HUB_L = 103; // left hub's left edge; plates load leftward from here
const HUB_R = 267; // right hub's right edge; plates load rightward from here

/**
 * The week's bar — the squad room's hero. One plate per completed session in that
 * lifter's color; the collars clamp where Monday's declaration set them. Bare sleeve
 * inside the collars is the work remaining; when the last plate seats flush the bar
 * is "ironclad" (collars glint). There are deliberately no ghost plates.
 */
export function WeeksBar({ declared, sessions, showTicks = true, width = 370 }: WeeksBarProps) {
  const cap = Math.min(declared, 8);
  const leftSlots = Math.ceil(cap / 2);
  const rightSlots = Math.floor(cap / 2);

  // sessions alternate sleeves (L, R, L, R…) while capacity remains
  const left: WeeksBarSession[] = [];
  const right: WeeksBarSession[] = [];
  for (const s of sessions.slice(0, cap)) {
    const preferLeft = left.length <= right.length && left.length < leftSlots;
    if (preferLeft || right.length >= rightSlots) left.push(s);
    else right.push(s);
  }

  const ironclad = declared > 0 && sessions.length >= declared;
  const scale = width / DESIGN_W;

  const leftSlotX = (i: number) => HUB_L - PLATE_W - SLOT * (i - 1); // i is 1-based
  const rightSlotX = (i: number) => HUB_R + SLOT * (i - 1);

  const els: React.ReactNode[] = [
    <div key="slvL" className="ox-bar__sleeve" style={{ left: 14, width: 89, top: 24 }} />,
    <div key="slvR" className="ox-bar__sleeve" style={{ left: HUB_R, width: 89, top: 24 }} />,
    <div key="shaft" className="ox-bar__shaft" style={{ left: 112, width: 146, top: 26 }} />,
    <div key="hubL" className="ox-bar__hub" style={{ left: HUB_L, top: 19 }} />,
    <div key="hubR" className="ox-bar__hub" style={{ left: 258, top: 19 }} />,
  ];

  left.forEach((s, i) =>
    els.push(
      <div key={`pL${i}`} className="ox-plate" style={{ left: leftSlotX(i + 1), top: 0, background: s.color }}>
        <span className="ox-plate__sheen" />
      </div>
    )
  );
  right.forEach((s, i) =>
    els.push(
      <div key={`pR${i}`} className="ox-plate" style={{ left: rightSlotX(i + 1), top: 0, background: s.color }}>
        <span className="ox-plate__sheen" />
      </div>
    )
  );

  if (showTicks) {
    for (let i = left.length + 1; i <= leftSlots; i++)
      els.push(<div key={`tL${i}`} className="ox-bar__tick" style={{ left: leftSlotX(i) + 6.5, top: 12 }} />);
    for (let i = right.length + 1; i <= rightSlots; i++)
      els.push(<div key={`tR${i}`} className="ox-bar__tick" style={{ left: rightSlotX(i) + 6.5, top: 12 }} />);
  }

  if (leftSlots > 0)
    els.push(<Collar key="cL" x={leftSlotX(leftSlots) - 9} />);
  if (rightSlots > 0)
    els.push(<Collar key="cR" x={rightSlotX(rightSlots) + PLATE_W} />);

  return (
    <div
      className={ironclad ? "ox-bar ox-bar--ironclad" : "ox-bar"}
      style={{ width, height: 64 * scale }}
    >
      <div style={{ width: DESIGN_W, height: 64, transform: `scale(${scale})`, transformOrigin: "top left", position: "relative" }}>
        {els}
      </div>
    </div>
  );
}

export interface PlateProps {
  /** Lifter color fill. */
  color: string;
  /** Height in px (width scales with it). Default 58. */
  height?: number;
}

/**
 * A single session plate in a lifter's color — the unit of effort everywhere in GymSync.
 * Standalone use: shop/cosmetic previews, legends, system-lines.
 */
export function Plate({ color, height = 58 }: PlateProps) {
  const w = (15 / 58) * height;
  return (
    <span className="ox-plate" style={{ position: "relative", display: "inline-block", width: w, height, background: color }}>
      <span className="ox-plate__sheen" />
    </span>
  );
}

export interface CollarProps {
  /** Absolute x within an ox-bar (internal use); omit for inline display. */
  x?: number;
}

/**
 * The bar collar — clamps at the declared weekly goal. Bare sleeve inside it is work
 * remaining; a plate seated flush against it means the week is ironclad.
 */
export function Collar({ x }: CollarProps) {
  const style: React.CSSProperties =
    x === undefined ? { position: "relative", display: "inline-block" } : { left: x, top: 17 };
  return (
    <span className="ox-collar" style={style}>
      <span className="ox-collar__lever" />
    </span>
  );
}

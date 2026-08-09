import React from "react";

export interface ExtrudedButtonProps {
  /** Visual weight: `face` (neutral, default) or `accent` (sky blue — the one thing to act on). */
  variant?: "face" | "accent";
  /** `sm` tightens padding and type for inline/chip placements. */
  size?: "md" | "sm";
  /** Stretch to full width with content justified apart (routine buttons, sheet CTAs). */
  wide?: boolean;
  onClick?: () => void;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}

/**
 * The Onyx 3D button: a face sitting proud on a darker lip; pressing sinks it.
 * Every tappable surface in GymSync uses this extrusion — if it doesn't sit proud, it isn't tappable.
 */
export function ExtrudedButton({
  variant = "face",
  size = "md",
  wide = false,
  onClick,
  children,
  style,
}: ExtrudedButtonProps) {
  const cls = [
    "ox-btn",
    variant === "accent" && "ox-btn--accent",
    size === "sm" && "ox-btn--sm",
    wide && "ox-btn--wide",
  ]
    .filter(Boolean)
    .join(" ");
  return (
    <button type="button" className={cls} onClick={onClick} style={style}>
      {children}
    </button>
  );
}

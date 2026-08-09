import React from "react";

export interface AvatarChipProps {
  /** Two-letter initials shown in the chip. */
  initials: string;
  /** The member's dedicated lifter color (their plates use the same hue). */
  color: string;
  /** Diameter in px. Default 34. */
  size?: number;
  style?: React.CSSProperties;
}

/**
 * A crew member's avatar: a filled circle in their dedicated lifter color with initials.
 * The same color identifies their plates on the week's bar.
 */
export function AvatarChip({ initials, color, size = 34, style }: AvatarChipProps) {
  return (
    <span
      className="ox-avatar"
      style={{ width: size, height: size, background: color, fontSize: size * 0.32, ...style }}
    >
      {initials}
    </span>
  );
}

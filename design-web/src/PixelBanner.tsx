import React from "react";

export interface PixelBannerProps {
  /** Cloth color (any CSS color; violet #6b4fd6 and gold #c39a1e are the house cloths). */
  color: string;
  /** Emblem drawn in light pixels on the cloth. */
  emblem?: "plate" | "bar" | "chalk" | "none";
  /** Gold chevron pairs earned by perfect weeks (0–2 shown on the cloth's tail). */
  chevrons?: 0 | 1 | 2;
  /** Rendered width in px. Default 24. */
  width?: number;
}

/**
 * A Terraria-style pixel-cloth banner hung from the rail. Crews earn chevrons for
 * perfect weeks; cloths and emblems are chalk-shop cosmetics. Never emoji.
 */
export function PixelBanner({ color, emblem = "none", chevrons = 0, width = 24 }: PixelBannerProps) {
  const light = "rgba(255,255,255,.78)";
  return (
    <span className="ox-banner" style={{ width, height: (44 / 24) * width }}>
      <svg viewBox="0 -3 20 34" width={width} height={(44 / 24) * width}>
        {/* rod */}
        <rect x={1} y={-3} width={18} height={3.6} fill="#4a3a28" />
        <rect x={1} y={-3} width={18} height={1.2} fill="#6f583a" />
        {/* cloth: swallowtail */}
        <path d="M3,0 H17 V30 L10,25 L3,30 Z" fill={color} />
        <rect x={5} y={4} width={10} height={13} fill="rgba(255,255,255,.10)" />
        <path d="M3,24 L10,25 L3,30 Z M17,24 L10,25 L17,30 Z" fill="rgba(0,0,0,.22)" />
        <path d="M3,0 H17 V30 L10,25 L3,30 Z" fill="none" stroke="rgba(0,0,0,.5)" strokeWidth={1} />
        {/* emblem */}
        {emblem === "plate" && (
          <g fill={light}>
            <rect x={9} y={5} width={2} height={2} />
            <rect x={8} y={7} width={4} height={2} />
            <rect x={7} y={9} width={6} height={4} />
            <rect x={8} y={13} width={4} height={2} />
          </g>
        )}
        {emblem === "bar" && (
          <g fill={light}>
            <rect x={6} y={5} width={8} height={2} />
            <rect x={8} y={7} width={4} height={7} />
            <rect x={6} y={14} width={8} height={2} />
          </g>
        )}
        {emblem === "chalk" && (
          <g fill={light}>
            <rect x={6} y={6} width={2} height={5} />
            <rect x={12} y={6} width={2} height={5} />
            <rect x={9} y={4} width={2} height={7} />
            <rect x={6} y={11} width={8} height={3} />
          </g>
        )}
        {/* chevrons */}
        {chevrons >= 1 && (
          <polyline points="6,20 10,17.5 14,20" fill="none" stroke="#e8c33a" strokeWidth={1.6} />
        )}
        {chevrons >= 2 && (
          <polyline points="6,23 10,20.5 14,23" fill="none" stroke="#e8c33a" strokeWidth={1.6} />
        )}
      </svg>
    </span>
  );
}

export interface BannerRailProps {
  /** The hung banners (PixelBanner children). */
  children?: React.ReactNode;
  /** Streak length shown by the flame at the right end. */
  weeks?: number;
  /** Rail width in px. Default 370. */
  width?: number;
}

/**
 * The steel rail the crew's banners hang from, with the streak flame at its right end.
 * The streak counts weeks of showing up — a low honest bar, distinct from perfect weeks.
 */
export function BannerRail({ children, weeks, width = 370 }: BannerRailProps) {
  return (
    <div style={{ position: "relative", width, height: 56, fontFamily: "var(--onyx-font)" }}>
      <div className="ox-rail" style={{ width }} />
      <div className="ox-rail__hang">{children}</div>
      {weeks !== undefined && (
        <span className="ox-flame" style={{ position: "absolute", right: 0, top: 10 }}>
          <svg width={13} height={16} viewBox="0 0 12 15">
            <path
              d="M6 0 C7.6 3 10 4.2 10 8.2 A4 4 0 0 1 2 8.2 C2 6 3 5.4 3.6 4.2 C4.2 6 5.2 6.2 6 5 C6.6 3.8 6.2 2 6 0Z"
              fill="#868B95"
            />
          </svg>
          <span className="ox-klabel" style={{ color: "var(--onyx-t78)" }}>
            {weeks} WKS
          </span>
        </span>
      )}
    </div>
  );
}

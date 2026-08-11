import React from "react";

export interface KLabelProps {
  /** Semantic tone: default neutral, `gold` debt/goal marks, `green` good standing, `accent` presence/action (sky), `dim` tertiary. */
  tone?: "default" | "gold" | "green" | "accent" | "dim";
  children?: React.ReactNode;
  style?: React.CSSProperties;
}

/**
 * The Onyx k-label: 10pt/800 tracked-uppercase utility text used for counts,
 * section headers, and metadata lines. Never used for body copy.
 */
export function KLabel({ tone = "default", children, style }: KLabelProps) {
  const cls = [
    "ox-klabel",
    tone === "gold" && "ox-klabel--gold",
    tone === "green" && "ox-klabel--green",
    tone === "accent" && "ox-klabel--accent",
    tone === "dim" && "ox-klabel--dim",
  ]
    .filter(Boolean)
    .join(" ");
  return (
    <span className={cls} style={style}>
      {children}
    </span>
  );
}

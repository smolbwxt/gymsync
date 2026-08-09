import React from "react";

export interface KLabelProps {
  /** Semantic tone: default neutral, `gold` for debt/goal marks, `green` for good standing, `dim` for tertiary. */
  tone?: "default" | "gold" | "green" | "dim";
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

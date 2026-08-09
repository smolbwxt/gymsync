import React from "react";
import { KLabel } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-flex", flexDirection: "column", gap: 10 }}>{children}</div>
);

export const Tones = () => (
  <Ground>
    <KLabel>5 OF 12 · EST. MAR '26</KLabel>
    <KLabel tone="gold">2 TO THE COLLARS</KLabel>
    <KLabel tone="green">✓ SQUARE WITH THE CREW</KLabel>
    <KLabel tone="dim">PREDICTIONS FROM YOUR OWN HISTORY</KLabel>
  </Ground>
);

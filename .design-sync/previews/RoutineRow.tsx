import React from "react";
import { RoutineRow } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "flex", flexDirection: "column", gap: 10, width: 350 }}>{children}</div>
);

export const Confirmed = () => (
  <Ground>
    <RoutineRow name="Bench Press" scheme="4 × 8 · TOP SET" prediction="225" state="confirmed" />
  </Ground>
);

export const Tunable = () => (
  <Ground>
    <RoutineRow name="Cable Fly" scheme="3 × 12" prediction="42.5" />
    <RoutineRow name="Weighted Dip" scheme="3 × 8" prediction="+45" />
  </Ground>
);

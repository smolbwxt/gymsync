import React from "react";
import { TuneStepper } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-block", width: 350 }}>{children}</div>
);

export const InclinePress = () => (
  <Ground>
    <TuneStepper
      name="Incline Dumbbell Press"
      scheme="3 × 10"
      value={70}
      context="LAST: 65 × 10 @ RPE 7 → +5"
      holdLabel="HOLD AT 65"
    />
  </Ground>
);

export const HeavySquat = () => (
  <Ground>
    <TuneStepper
      name="Back Squat"
      scheme="5 × 5 · TOP SET"
      value={315}
      context="LAST: 305 × 5 @ RPE 8 → +10"
      holdLabel="HOLD AT 305"
    />
  </Ground>
);

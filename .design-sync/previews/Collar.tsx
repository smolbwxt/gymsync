import React from "react";
import { Collar, Plate } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-flex", gap: 8, alignItems: "center" }}>{children}</div>
);

export const Solo = () => (
  <Ground>
    <Collar />
  </Ground>
);

export const FlushWithPlate = () => (
  <Ground>
    <Plate color="#2FA45C" />
    <Collar />
  </Ground>
);

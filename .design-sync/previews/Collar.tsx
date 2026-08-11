import React from "react";
import { Clip, Collar, Plate } from "@gymsync/onyx";

const Ground = ({ children, gap = 8 }: { children: React.ReactNode; gap?: number }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-flex", gap, alignItems: "center" }}>{children}</div>
);

export const Solo = () => (
  <Ground>
    <Collar />
  </Ground>
);

export const FlushWithPlate = () => (
  <Ground gap={2}>
    <Plate color="#2FA45C" />
    <Collar />
  </Ground>
);

export const ClipRetainers = () => (
  <Ground gap={10}>
    <Clip />
    <Clip gold />
  </Ground>
);

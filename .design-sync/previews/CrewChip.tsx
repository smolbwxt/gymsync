import React from "react";
import { CrewChip } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-flex", gap: 10, alignItems: "center" }}>{children}</div>
);

export const HeaderRow = () => (
  <Ground>
    <CrewChip label="IC" color="#7C5CFF" active />
    <CrewChip label="SS" color="#2FA45C" notify />
    <CrewChip label="+" color="#2A303A" />
  </Ground>
);

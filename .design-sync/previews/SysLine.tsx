import React from "react";
import { SysLine } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "flex", flexDirection: "column", gap: 12, width: 340 }}>{children}</div>
);

export const Cheerable = () => (
  <Ground>
    <SysLine color="#2FA45C" text="DANI PUT A PLATE ON THE BAR · PULL DAY B" cheers={2} />
  </Ground>
);

export const Plain = () => (
  <Ground>
    <SysLine color="#C9A227" text="TESS PUT A PLATE ON THE BAR" />
  </Ground>
);

import React from "react";
import { ExtrudedButton, KLabel } from "@gymsync/onyx";

const Ground = ({ children, width }: { children: React.ReactNode; width?: number }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-block", width }}>{children}</div>
);

export const Face = () => (
  <Ground>
    <ExtrudedButton>RACK IT</ExtrudedButton>
  </Ground>
);

export const Accent = () => (
  <Ground>
    <ExtrudedButton variant="accent">I'M IN</ExtrudedButton>
  </Ground>
);

export const Small = () => (
  <Ground>
    <ExtrudedButton size="sm">OPEN ›</ExtrudedButton>
  </Ground>
);

export const WideRoutine = () => (
  <Ground width={340}>
    <ExtrudedButton wide style={{ padding: "11px 12px" }}>
      <span style={{ fontSize: 12.5, fontWeight: 800 }}>▸ CHEST DAY A</span>
      <KLabel style={{ color: "var(--onyx-n700)" }}>FRI 5:30 ›</KLabel>
    </ExtrudedButton>
  </Ground>
);

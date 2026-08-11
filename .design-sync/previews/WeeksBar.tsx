import React from "react";
import { WeeksBar } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-block" }}>{children}</div>
);

export const MidWeek = () => (
  <Ground>
    <WeeksBar declared={7} completed={5} />
  </Ground>
);

export const FreshMonday = () => (
  <Ground>
    <WeeksBar declared={7} completed={0} />
  </Ground>
);

export const Ironclad = () => (
  <Ground>
    <WeeksBar declared={7} completed={7} />
  </Ground>
);

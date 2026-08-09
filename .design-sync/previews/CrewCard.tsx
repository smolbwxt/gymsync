import React from "react";
import { CrewCard } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-block", width: 350 }}>{children}</div>
);

const members = [
  { initials: "MK", color: "#E8834A" },
  { initials: "DN", color: "#2FA45C" },
  { initials: "YO", color: "#3AB5F5", owes: 20 },
  { initials: "TS", color: "#C9A227" },
];

export const IronChurch = () => (
  <Ground>
    <CrewCard members={members} routineName="CHEST DAY A" routineTime="FRI 5:30" />
  </Ground>
);

export const AllSquare = () => (
  <Ground>
    <CrewCard
      members={members.map((m) => ({ ...m, owes: 0 }))}
      routineName="PULL DAY B"
      routineTime="MON 6:00"
    />
  </Ground>
);

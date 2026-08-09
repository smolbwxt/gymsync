import React from "react";
import { AvatarChip } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-flex", gap: 10, alignItems: "center" }}>{children}</div>
);

export const TheCrew = () => (
  <Ground>
    <AvatarChip initials="MK" color="#E8834A" />
    <AvatarChip initials="DN" color="#2FA45C" />
    <AvatarChip initials="YO" color="#3AB5F5" />
    <AvatarChip initials="TS" color="#C9A227" />
  </Ground>
);

export const Sizes = () => (
  <Ground>
    <AvatarChip initials="MK" color="#E8834A" size={44} />
    <AvatarChip initials="MK" color="#E8834A" size={34} />
    <AvatarChip initials="MK" color="#E8834A" size={24} />
  </Ground>
);

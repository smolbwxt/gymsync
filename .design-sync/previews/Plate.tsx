import React from "react";
import { Plate } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-flex", gap: 8, alignItems: "center" }}>{children}</div>
);

export const CrewIron = () => (
  <Ground>
    <Plate />
    <Plate />
    <Plate />
  </Ground>
);

export const Sizes = () => (
  <Ground>
    <Plate height={74} />
    <Plate height={48} />
    <Plate height={20} />
  </Ground>
);

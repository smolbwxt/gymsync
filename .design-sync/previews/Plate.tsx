import React from "react";
import { Plate } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-flex", gap: 8, alignItems: "center" }}>{children}</div>
);

export const LifterColors = () => (
  <Ground>
    <Plate color="#E8834A" />
    <Plate color="#2FA45C" />
    <Plate color="#3AB5F5" />
    <Plate color="#C9A227" />
  </Ground>
);

export const Sizes = () => (
  <Ground>
    <Plate color="#3AB5F5" height={58} />
    <Plate color="#3AB5F5" height={40} />
    <Plate color="#3AB5F5" height={20} />
  </Ground>
);

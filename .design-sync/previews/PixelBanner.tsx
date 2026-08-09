import React from "react";
import { PixelBanner } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-flex", gap: 10, alignItems: "flex-start" }}>{children}</div>
);

export const HouseCloths = () => (
  <Ground>
    <PixelBanner color="#6b4fd6" emblem="plate" />
    <PixelBanner color="#6b4fd6" emblem="bar" />
    <PixelBanner color="#c39a1e" emblem="chalk" />
  </Ground>
);

export const Chevroned = () => (
  <Ground>
    <PixelBanner color="#6b4fd6" emblem="plate" chevrons={1} />
    <PixelBanner color="#6b4fd6" emblem="plate" chevrons={2} />
  </Ground>
);

export const Large = () => (
  <Ground>
    <PixelBanner color="#c39a1e" emblem="bar" chevrons={2} width={40} />
  </Ground>
);

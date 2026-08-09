import React from "react";
import { BannerRail, PixelBanner } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-block" }}>{children}</div>
);

export const SevenWeekStreak = () => (
  <Ground>
    <BannerRail weeks={7}>
      <PixelBanner color="#6b4fd6" emblem="plate" chevrons={2} />
      <PixelBanner color="#6b4fd6" emblem="bar" />
      <PixelBanner color="#c39a1e" emblem="chalk" chevrons={1} />
    </BannerRail>
  </Ground>
);

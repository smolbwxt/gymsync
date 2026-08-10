import React from "react";
import { TabBar } from "@gymsync/onyx";

const items = [
  { icon: "⌂", label: "HOME" },
  { icon: "◫", label: "HOME GYM" },
  { icon: "▣", label: "SHOP" },
  { icon: "◯", label: "YOU" },
];

export const HomeGymActive = () => (
  <div style={{ background: "#0A0B0D", padding: "24px 0 0", borderRadius: 12, display: "inline-block", width: 360 }}>
    <TabBar items={items} activeIndex={1} />
  </div>
);

import React from "react";
import { WeeksBar } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-block" }}>{children}</div>
);

const YOU = "#3AB5F5";
const MARCUS = "#E8834A";
const DANI = "#2FA45C";
const TESS = "#C9A227";

export const MidWeek = () => (
  <Ground>
    <WeeksBar
      declared={7}
      sessions={[
        { color: MARCUS, member: "Marcus" },
        { color: TESS, member: "Tess" },
        { color: YOU, member: "You" },
        { color: MARCUS, member: "Marcus" },
        { color: DANI, member: "Dani" },
      ]}
    />
  </Ground>
);

export const FreshMonday = () => (
  <Ground>
    <WeeksBar declared={7} sessions={[]} />
  </Ground>
);

export const Ironclad = () => (
  <Ground>
    <WeeksBar
      declared={6}
      sessions={[
        { color: MARCUS, member: "Marcus" },
        { color: DANI, member: "Dani" },
        { color: YOU, member: "You" },
        { color: TESS, member: "Tess" },
        { color: MARCUS, member: "Marcus" },
        { color: DANI, member: "Dani" },
      ]}
    />
  </Ground>
);

export const QuietNoTicks = () => (
  <Ground>
    <WeeksBar declared={4} sessions={[{ color: YOU, member: "You" }]} showTicks={false} />
  </Ground>
);

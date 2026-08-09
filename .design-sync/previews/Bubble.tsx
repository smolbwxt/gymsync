import React from "react";
import { Bubble } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "inline-flex", flexDirection: "column", gap: 8, width: 300 }}>{children}</div>
);

export const Incoming = () => (
  <Ground>
    <Bubble direction="in">friday we're going heavy</Bubble>
    <Bubble direction="in" tail>
      bring the belt
    </Bubble>
  </Ground>
);

export const Outgoing = () => (
  <Ground>
    <Bubble direction="out" style={{ alignSelf: "flex-end" }}>
      got the chalk
    </Bubble>
    <Bubble direction="out" tail style={{ alignSelf: "flex-end" }}>
      settling my burpees before we start
    </Bubble>
  </Ground>
);

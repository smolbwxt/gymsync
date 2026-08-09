import React from "react";
import { Bubble, MsgRow } from "@gymsync/onyx";

const Ground = ({ children }: { children: React.ReactNode }) => (
  <div style={{ background: "#0A0B0D", padding: 24, borderRadius: 12, display: "flex", flexDirection: "column", width: 320 }}>{children}</div>
);

export const IncomingRun = () => (
  <Ground>
    <MsgRow>
      <Bubble direction="in">friday we're going heavy</Bubble>
    </MsgRow>
    <MsgRow endOfRun avatar={{ initials: "MK", color: "#E8834A" }}>
      <Bubble direction="in" tail>
        bring the belt
      </Bubble>
    </MsgRow>
  </Ground>
);

export const OutgoingReply = () => (
  <Ground>
    <MsgRow me>
      <Bubble direction="out">got it</Bubble>
    </MsgRow>
    <MsgRow me endOfRun>
      <Bubble direction="out" tail>
        settling my burpees first
      </Bubble>
    </MsgRow>
  </Ground>
);

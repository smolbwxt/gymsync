import React from "react";
import { Bubble, ChatWidget, MsgRow, SysLine } from "@gymsync/onyx";

export const LiveTail = () => (
  <div style={{ background: "#0A0B0D", padding: "24px 24px 0", borderRadius: 12, display: "inline-block", width: 360 }}>
    <ChatWidget unread={3} height={290}>
      <div style={{ marginBottom: 10 }}>
        <SysLine color="#2FA45C" text="DANI PUT A PLATE ON THE BAR" cheers={2} />
      </div>
      <MsgRow endOfRun avatar={{ initials: "MK", color: "#E8834A" }}>
        <Bubble direction="in" tail style={{ fontSize: 13.5, padding: "7px 11px" }}>
          friday we're going heavy. bring the belt
        </Bubble>
      </MsgRow>
      <MsgRow me endOfRun>
        <Bubble direction="out" tail style={{ fontSize: 13.5, padding: "7px 11px" }}>
          got the chalk. settling my burpees first
        </Bubble>
      </MsgRow>
      <MsgRow endOfRun avatar={{ initials: "TS", color: "#C9A227" }}>
        <Bubble direction="in" tail style={{ fontSize: 13.5, padding: "7px 11px" }}>
          bringing the speaker
        </Bubble>
      </MsgRow>
    </ChatWidget>
  </div>
);

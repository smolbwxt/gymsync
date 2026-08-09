import React from "react";
import { KLabel } from "./KLabel";
import { ExtrudedButton } from "./ExtrudedButton";

export interface ChatWidgetProps {
  /** Unread count shown in the accent pill. */
  unread?: number;
  /** The live tail of the thread: MsgRow/SysLine children, bottom-anchored. */
  children?: React.ReactNode;
  /** Composer placeholder. Default "Message". */
  placeholder?: string;
  /** Tapping anywhere expands to the full-screen thread. */
  onExpand?: () => void;
  /** Height in px. Default 300. */
  height?: number;
  style?: React.CSSProperties;
}

/**
 * The squad room's chat window — the page's bottom half. Shows the live tail of the
 * crew thread bottom-anchored above a compact composer; tapping expands to the
 * full-screen thread. Header carries the unread pill and the extruded OPEN chip.
 */
export function ChatWidget({ unread, children, placeholder = "Message", onExpand, height = 300, style }: ChatWidgetProps) {
  return (
    <div className="ox-chatwidget" style={{ height, ...style }} onClick={onExpand}>
      <div className="ox-chatwidget__head">
        <KLabel>THE CHAT</KLabel>
        {unread !== undefined && unread > 0 && <span className="ox-pill">{unread}</span>}
        <span style={{ flex: 1 }} />
        <ExtrudedButton size="sm" style={{ letterSpacing: ".1em" }}>OPEN ›</ExtrudedButton>
      </div>
      <div className="ox-chatwidget__body">{children}</div>
      <div className="ox-composer" style={{ paddingTop: 6 }}>
        <button type="button" className="ox-composer__plus" style={{ width: 30, height: 30, fontSize: 15 }}>＋</button>
        <div className="ox-composer__field" style={{ padding: "6px 6px 6px 12px", fontSize: 12.5 }}>
          <span style={{ flex: 1 }}>{placeholder}</span>
          <span style={{ fontSize: 13 }}>🎤</span>
        </div>
      </div>
    </div>
  );
}

import React from "react";

export interface TabBarItem {
  /** Glyph shown above the label (text/symbol). */
  icon: string;
  /** Uppercase label. */
  label: string;
}

export interface TabBarProps {
  /** The tabs in order. GymSync ships HOME · HOME GYM · SHOP · YOU. */
  items: TabBarItem[];
  /** Index of the active tab (accent-colored). */
  activeIndex?: number;
  onSelect?: (index: number) => void;
}

/**
 * The app's bottom tab bar: four destinations, active tab in accent. Sits on the
 * page ground with a hairline divider above.
 */
export function TabBar({ items, activeIndex = 0, onSelect }: TabBarProps) {
  return (
    <div className="ox-tabbar">
      {items.map((it, i) => (
        <button
          key={it.label}
          type="button"
          className={i === activeIndex ? "ox-tabbar__item ox-tabbar__item--active" : "ox-tabbar__item"}
          onClick={() => onSelect?.(i)}
        >
          <div className="ox-tabbar__icon">{it.icon}</div>
          <div className="ox-tabbar__label">{it.label}</div>
        </button>
      ))}
    </div>
  );
}

import React from "react";
import { KLabel } from "./KLabel";
import { ExtrudedButton } from "./ExtrudedButton";

export interface RoutineRowProps {
  /** Exercise name. */
  name: string;
  /** Set scheme (e.g. "4 × 8 · TOP SET"). */
  scheme: string;
  /** Predicted working weight, as display text (e.g. "225", "+45", "42.5"). */
  prediction: string;
  /** `confirmed` = user locked it (green check); `tunable` = tap to tune (accent). */
  state?: "tunable" | "confirmed";
  onTap?: () => void;
}

/**
 * One exercise in the routine preview: name + scheme with the predicted working weight
 * from the suggestion engine. Confirmed weights show green and prefill on game day;
 * tunable ones invite a tap to open the TuneStepper.
 */
export function RoutineRow({ name, scheme, prediction, state = "tunable", onTap }: RoutineRowProps) {
  const confirmed = state === "confirmed";
  return (
    <div className="ox-routinerow" style={{ cursor: "pointer" }} onClick={onTap}>
      <div style={{ display: "flex", flexDirection: "column", flex: 1, gap: 4 }}>
        <span className="ox-routinerow__name">{name}</span>
        <KLabel>{scheme}</KLabel>
      </div>
      <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 3 }}>
        <span className="ox-routinerow__num" style={{ color: confirmed ? "var(--onyx-green)" : "var(--onyx-ac)" }}>
          {prediction}
          {confirmed ? " ✓" : ""}
        </span>
        <KLabel tone={confirmed ? "green" : "default"}>{confirmed ? "CONFIRMED" : "TAP TO TUNE ›"}</KLabel>
      </div>
    </div>
  );
}

export interface TuneStepperProps {
  /** Exercise name shown in the header row. */
  name: string;
  /** Set scheme. */
  scheme: string;
  /** Current value on the stepper. */
  value: number;
  /** Unit label. Default "LB". */
  unit?: string;
  /** The reasoning line under the value (e.g. "LAST: 65 × 10 @ RPE 7 → +5"). */
  context?: string;
  /** Secondary action label (e.g. "HOLD AT 65"). */
  holdLabel?: string;
  onConfirm?: () => void;
  onHold?: () => void;
}

/**
 * The expanded tuning state of a routine row: stepper with the suggestion engine's
 * reasoning line, CONFIRM (locks the prediction — prefills on game day) and HOLD.
 */
export function TuneStepper({ name, scheme, value, unit = "LB", context, holdLabel, onConfirm, onHold }: TuneStepperProps) {
  return (
    <div className="ox-routinerow ox-routinerow--open">
      <div style={{ display: "flex", gap: 12, alignItems: "center" }}>
        <div style={{ display: "flex", flexDirection: "column", flex: 1, gap: 4 }}>
          <span className="ox-routinerow__name">{name}</span>
          <KLabel>{scheme}</KLabel>
        </div>
        <span className="ox-routinerow__num" style={{ color: "var(--onyx-ac)" }}>{value}</span>
      </div>
      <div style={{ height: 1, background: "var(--onyx-dvs)", margin: "12px -15px" }} />
      <div className="ox-stepper">
        <ExtrudedButton style={{ width: 44 }}>−</ExtrudedButton>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 3 }}>
          <span className="ox-stepper__val">
            {value} <span style={{ fontSize: 11, color: "var(--onyx-n700)" }}>{unit}</span>
          </span>
          {context && <KLabel>{context}</KLabel>}
        </div>
        <ExtrudedButton style={{ width: 44 }}>＋</ExtrudedButton>
      </div>
      <div style={{ display: "flex", gap: 9, marginTop: 12 }}>
        <ExtrudedButton variant="accent" style={{ flex: 1, padding: 11 }} onClick={onConfirm}>
          CONFIRM {value}
        </ExtrudedButton>
        {holdLabel && (
          <ExtrudedButton style={{ padding: "11px 13px" }} onClick={onHold}>
            {holdLabel}
          </ExtrudedButton>
        )}
      </div>
    </div>
  );
}

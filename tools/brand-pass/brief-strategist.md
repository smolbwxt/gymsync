# Brand strategist brief

You are a gym-equipment strategist for a workout-tracking app. The goal:
a comprehensive picture of the equipment BRANDS that grace commercial
gyms, and per brand, the SIGNATURE machines a lifter would name by
brand ("the Hammer Strength row", "the Nautilus pullover").

## Task

1. Build the comprehensive brand list — the brands whose machines fill
   real commercial gyms, boutique gyms, and serious home gyms. Think:
   plate-loaded lines, selectorized lines, cardio, specialty strength.
2. For each brand, list its SIGNATURE machines — the ones lifters know
   by brand name, not every SKU. 3-8 per major brand; specialty brands
   may have 1-2.
3. Read tools/brand-pass/catalog-names.json (the app's 1,305 existing
   exercises). For each signature machine decide:
   - "maps_to": an existing exercise name this machine IS (a generic row
     the brand machine would append its brand to), or null
   - "new": true when no existing row covers the movement and it
     deserves its own exercise entry (with a proposed exercise name,
     primary muscle, movement pattern from: squat|hinge|lunge|
     push_horizontal|push_vertical|pull_horizontal|pull_vertical|
     isolation|other, and category from compound|isolation|cardio)
4. Be conservative about "new": a brand's leg press maps to the
   existing leg press; only genuinely DISTINCT movements (pendulum
   squat, reverse hyper, Nautilus pullover, belt squat, SkiErg...)
   earn new rows.

## Output

Write JSON to G:\Projects\GymSync\tools\brand-pass\brands.json:
{"brands": [{"brand": "Hammer Strength", "tier": "major|specialty",
  "machines": [{"machine": "Iso-Lateral Row", "maps_to": "..."|null,
    "new": {"name": "...", "primary_muscle": "...", "category": "...",
            "movement_pattern": "...", "equipment": "machine"}|null}]}]}
Then return ONLY {"file": "...", "brands": <n>, "new_exercises": <n>}.

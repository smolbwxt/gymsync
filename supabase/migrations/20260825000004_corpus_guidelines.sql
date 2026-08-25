-- Published guidelines and validated screening instruments (2026-08-25).
-- Owner: "Lets digest as much officially published authoritative
-- documentation as we can get our hands on."
--
-- Deliberately its OWN area. Everything else in corpus_findings is
-- distilled practitioner content from YouTube; these are position stands
-- and validated instruments, and Coach should be able to weight them
-- differently and cite them BY NAME. basis='guideline' marks that.
--
-- Sources digested in full (text extracted and read):
--   * PAR-Q+ 2021/2025, PAR-Q+ Collaboration (eparmedx.com)
--   * NSCA Youth Resistance Training: Updated Position Statement Paper,
--     Faigenbaum et al., J Strength Cond Res 2009
-- Sources digested at summary level only (full text paywalled):
--   * ACOG Committee Opinion 804, Physical Activity and Exercise During
--     Pregnancy and the Postpartum Period (2020)
--   * CSEP Get Active Questionnaire for Pregnancy / for Postpartum
--
-- HONEST LIMITATION recorded rather than papered over: the enumerated
-- absolute and relative contraindication lists for pregnancy sit behind
-- paywalls and were NOT verified here. That is not a blocker, because the
-- correct product behaviour is the same either way and both sources state
-- it: pregnancy routes to the person's clinician. The app must not carry
-- a contraindication list it could not read.

INSERT INTO public.corpus_findings (area, topic, claim, basis, confidence, sport, quantities) VALUES
  ('guideline', 'screening', 'PAR-Q+ is the validated self-screening instrument for physical activity readiness: seven general health questions, all ages, with a physical-activity clearance valid up to 12 months.', 'guideline', 'strong', NULL, '{"questions":7,"validity_months":12}'::jsonb),
  ('guideline', 'screening', 'PAR-Q+ decision rule: all seven answered NO means cleared to become more physically active; any YES routes the person to the follow-up condition pages or a clinician conversation.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'screening', 'PAR-Q+ question 1 screens a doctor-diagnosed heart condition or high blood pressure — the highest-priority stop sign in a self-report screen.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'screening', 'PAR-Q+ question 2 screens chest pain at rest, during daily living, or during physical activity. Any of the three is a referral trigger, not just exertional pain.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'screening', 'PAR-Q+ question 3 screens balance loss from dizziness or loss of consciousness within 12 months, explicitly excluding dizziness from over-breathing during vigorous exercise.', 'guideline', 'strong', NULL, '{"lookback_months":12}'::jsonb),
  ('guideline', 'screening', 'PAR-Q+ also screens: any other chronic condition, current prescribed medication for a chronic condition, a bone/joint/soft-tissue problem that activity could worsen, and doctor-advised medically supervised activity only.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'screening', 'PAR-Q+ question 6 explicitly excludes past musculoskeletal problems that do not limit current activity — a healed injury is not a screening flag.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'screening', 'PAR-Q+ instructs DELAY, not clearance, during temporary illness such as a cold or fever: wait until recovered before becoming more active.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'screening', 'PAR-Q+ instructs that pregnancy means consulting a health care practitioner or qualified exercise professional before becoming more physically active, rather than self-clearing.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'screening', 'PAR-Q+ treats a change in health status as invalidating a prior clearance: the person re-screens or speaks to a clinician before continuing a program.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'screening', 'PAR-Q+ follow-up organises conditions into ten categories: arthritis/osteoporosis/back, cancer, heart or cardiovascular, high blood pressure, metabolic, respiratory, mental-health/learning, spinal cord injury, stroke, and other or multiple conditions.', 'guideline', 'strong', NULL, '{"categories":10}'::jsonb),
  ('guideline', 'screening', 'Across PAR-Q+ follow-up categories the recurring discriminator is CONTROL: difficulty controlling a condition with prescribed medication or therapy escalates it toward referral.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'screening', 'PAR-Q+ carries a parent/guardian/care-provider signature line, so a minor completing pre-activity screening is expected to have guardian involvement.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'youth', 'NSCA position stand: many benefits of adult resistance training are attainable by children and adolescents who follow age-specific guidelines. Youth resistance training is supported, not merely tolerated.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'youth', 'NSCA readiness criterion is behavioural, not chronological: a child should be emotionally mature enough to accept and follow directions and show competent balance and postural control, roughly age 6-7.', 'guideline', 'strong', NULL, '{"approx_age":"6-7"}'::jsonb),
  ('guideline', 'youth', 'NSCA general youth guidance: 1-3 sets of 6-15 repetitions on a variety of upper- and lower-body exercises, plus 1-3 sets of 3-6 repetitions for power exercises.', 'guideline', 'strong', NULL, '{"strength_sets":"1-3","strength_reps":"6-15","power_sets":"1-3","power_reps":"3-6"}'::jsonb),
  ('guideline', 'youth', 'NSCA youth progression by training age, intensity: novice 50-70% 1RM, intermediate 60-80%, advanced 70-85%. The advanced youth ceiling sits below typical adult advanced ceilings.', 'guideline', 'strong', NULL, '{"novice_pct":"50-70","intermediate_pct":"60-80","advanced_pct":"70-85"}'::jsonb),
  ('guideline', 'youth', 'NSCA youth progression by training age, volume: novice 1-2 sets of 10-15 reps, intermediate 2-3 sets of 8-12, advanced 3 or more sets of 6-10.', 'guideline', 'strong', NULL, '{"novice":"1-2x10-15","intermediate":"2-3x8-12","advanced":"3+x6-10"}'::jsonb),
  ('guideline', 'youth', 'NSCA youth rest intervals scale with training age: about 1 minute novice, 1-2 minutes intermediate, 2-3 minutes advanced.', 'guideline', 'strong', NULL, '{"novice_min":1,"intermediate_min":"1-2","advanced_min":"2-3"}'::jsonb),
  ('guideline', 'youth', 'NSCA youth frequency: 2-3 non-consecutive days per week for novice and intermediate, 3-4 days for advanced. Non-consecutive scheduling is stated explicitly.', 'guideline', 'strong', NULL, '{"novice":"2-3","intermediate":"2-3","advanced":"3-4"}'::jsonb),
  ('guideline', 'youth', 'NSCA load progression for youth: increase resistance gradually by roughly 5-10% once technique is sound and the current load is handled across the prescribed range.', 'guideline', 'strong', NULL, '{"increment_pct":"5-10"}'::jsonb),
  ('guideline', 'youth', 'NSCA sequences youth sessions with a 5-10 minute dynamic warm-up and closes with lower-intensity work and static stretching.', 'guideline', 'strong', NULL, '{"warmup_min":"5-10"}'::jsonb),
  ('guideline', 'youth', 'NSCA emphasises symmetrical muscular development, balance around joints, and dedicated abdominal and lower-back work in youth programs.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'youth', 'NSCA states youth must first learn each exercise correctly with a light load — an unloaded barbell is the given example — before intensity or volume progresses.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'youth', 'NSCA requires qualified instruction and supervision and a hazard-free environment as preconditions for youth resistance training, not optional extras.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'youth', 'NSCA rejects the claim that a strength prerequisite such as a 1.5x bodyweight squat is required before youth plyometric training; current research and clinical observation do not support it.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'youth', 'Growth cartilage in a maturing child sits at three sites — growth plates near long-bone ends, articular cartilage, and apophyses where major tendons attach — which is the anatomical basis of the injury concern.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'youth', 'NSCA advises periodised youth programs include periods of active rest, roughly 1-3 weeks between sport seasons, for physical and psychological recovery.', 'guideline', 'strong', NULL, '{"active_rest_weeks":"1-3"}'::jsonb),
  ('guideline', 'training_age', 'NSCA defines novice as up to about 2-3 months of consistent resistance training experience, OR an individual who has not trained for several months — detraining returns a lifter to novice.', 'guideline', 'strong', NULL, '{"novice_months":"0-3"}'::jsonb),
  ('guideline', 'training_age', 'NSCA defines intermediate as roughly 3-12 months of consistent resistance training, and advanced as at least 12 months with significant strength and power gains attained.', 'guideline', 'strong', NULL, '{"intermediate_months":"3-12","advanced_months":"12+"}'::jsonb),
  ('guideline', 'pregnancy', 'ACOG Committee Opinion 804 encourages aerobic AND strength conditioning before, during, and after pregnancy; exercise is beneficial for most people in pregnancy and postpartum.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'pregnancy', 'ACOG: those habitually performing vigorous-intensity aerobic activity before pregnancy can continue during pregnancy and postpartum, absent obstetric or medical contraindication.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'pregnancy', 'ACOG: light activity such as walking or pelvic floor work is permissible immediately postpartum when medically safe, with gradual resumption thereafter.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'pregnancy', 'ACOG frames the gate as obstetric or medical contraindication assessed by a clinician; an app cannot self-clear a pregnant user and should route to their provider.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'pregnancy', 'CSEP''s Get Active Questionnaire for Pregnancy is the pregnancy analogue of PAR-Q+: four questions, all-NO proceeds, any-YES routes to the health care provider.', 'guideline', 'strong', NULL, '{"questions":4}'::jsonb),
  ('guideline', 'pregnancy', 'CSEP pairs its pregnancy questionnaire with a Health Care Provider Consultation Form that enumerates absolute and relative contraindications — the clinician holds that list, not the app.', 'guideline', 'strong', NULL, NULL),
  ('guideline', 'pregnancy', 'CSEP published a Get Active Questionnaire for Postpartum in 2025, so postpartum screening is treated as its own gate rather than an extension of pregnancy screening.', 'guideline', 'moderate', NULL, NULL);

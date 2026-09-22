# Care statuses, sleep and activity wishes

The existing food bubble now displays the most important thought, in this order:
sleeping → sick → training fatigue → sleepy → food → play/training wish.
Only one bubble is visible, so messages do not stack over the creature's head.
The same projection, keyboard focus and modal-hiding behavior applies to all.

## Playable behavior and initial tuning

- **Sleepy (Zzz):** sleepiness increases by 1 per 20 engaged seconds, capped at
  100. The request starts at 40 (about 13 minutes of engaged activity). Offline
  awake time does not make the companion sleepy.
- **Tired (blue face):** training's existing +15 fatigue causes a warning at 50.
  At 50–70 fatigue, the training menu explicitly says “Train anyway” and warns
  of the 35% sickness chance per completed session. Above 70, training is blocked
  as before. No new punishment evolution or permanent stat loss is introduced.
- **Sick (green face/thermometer):** blocks play, training and battles until a
  complete sleep. Feeding, petting and cleanup remain available while awake.
  Existing virus/hygiene care is independent of this overtraining illness.
- **Sleep:** tap a health/Zzz bubble, or Tools → Sleep. A nap lasts 120 real
  seconds, including offline, stops roaming and active-time rewards, and
  recovers an additional 0.5 fatigue/second alongside normal passive recovery.
  Completing it clears sickness and sleepiness. It grants +2 discipline only
  if fatigue was ≥20, sleepiness ≥40, or the creature was sick at bedtime.
  Repeated unnecessary naps cannot farm discipline. Early wake keeps partial
  fatigue recovery but gives neither discipline nor sickness recovery.
- **Play wish:** animated bouncing ball; tapping it plays immediately. Tools →
  Play together also fulfills it. Adds +5 happiness and +3 base bond to ordinary
  play, with existing diminishing bond returns. Petting is still a distinct
  action and does not consume the play wish.
- **Training wish:** animated punching stick figure; tapping it opens Training.
  Any selected stat receives +1 extra point, or +5 for HP/MP, on completion.
  Stat caps still apply. Motivation is captured when training starts, so a wish
  expiring during the 30-second session does not revoke an earned bonus.
- Wishes alternate play/training, first after 180 eligible engaged seconds,
  then 240–420 seconds after the preceding wish ends. Each lasts 120 real
  seconds. New wishes wait while training, sick, tired, sleepy, asleep or showing
  a food craving. Missing one has no penalty. Existing wishes can expire offline.

Sleep cannot overlap training or battle. Sleeping blocks other care except
cleanup and waking; sickness blocks strenuous activities. Fullness and bathroom
time still advance normally during sleep. The creature currently rests in its
grounded idle pose; no new authored creature sleeping animation is claimed.

## Art and animation

Read-only inspection of the supplied Figma workshop did not locate the exact
requested status art. `scripts/ui/craving_bubble.gd` therefore draws replaceable
UI placeholders: Zzzs, tired/sick faces, bouncing ball and punching stick figure.
These are not exported Figma animations or AI-generated sprite sheets. Reduced
motion freezes animated icons; hidden bubbles do not animate. Existing food
icons remain the original exported Figma PNGs and were not changed.

## State and safety

`CareStatusRules` owns tuning, status selection, wish timing and deterministic
sickness rolls. `CareRules` applies rewards, recovery and validation; GameState
remains the only live mutation authority. Sickness rolls use a save-owned
sequence and stable identity, so retrying a failed completion gets the same roll.
Cancelled/relaunched sessions grant no reward or sickness and cannot reroll a
completed session. A new attempt after a cancelled session uses the same next
roll. Sleep/wish transitions trigger autosave; feeding/play/training/sleep
commands preserve the existing failed-save rollback behavior.

Save schema **v7** adds `care.status`. The v1–v6 migration chain preserves existing
identity, nature, progression, food cravings, inventory, layouts and waste.
Sleep remaining time, reward eligibility, illness and wish sequence/deadline
persist. Active training remains transient and is never resumed from a save.

## Verification

`tests/care_status_runner.gd` runs in isolated `--test-mode`, covering strict
validation, v6 envelope migration, timing, priority, all six training bonuses,
duplicate rewards, deterministic sickness, offline/reloaded sleep, early wake,
activity exclusion, cancellation and failed-save rollback. It deliberately
injects three save errors. Portrait UI checks cover all six status appearances at
360×640 and 390×844, plus reduced motion and actual bubble actions. Use
`--capture` with a graphical renderer for `/tmp/care-status-*.png` evidence.

Verified: 116 status checks in the graphical renderer, including both animation
poses; related care (75), training/decor (38), home migration (59), lifecycle (78),
persistence (31), food (36), care UI (27), and live battle (64) checks also pass.
The entire environment regression suite was not rerun for this change; the
separate environment issues noted in `FOOD_CARE_V6.md` are not claimed resolved.

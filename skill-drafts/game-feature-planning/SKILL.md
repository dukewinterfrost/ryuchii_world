---
name: game-feature-planning
description: Plan playable game features, prototypes, tuning workflows, and temporary assets from the existing game and the intended player experience. Use for feature design, game-feel changes, implementation-ready specifications, playtest revisions, and placeholder tracking.
---

# Game Feature Planning

Turn a desired player experience into a small playable experiment and an implementable feature. Keep reusable design guidance here; keep each game's decisions, tuning values, test evidence, and placeholders in that project's documentation.

## Ground the feature

- Inspect the actual game, its current feature, controls, content workflow, persistence, and tests before proposing replacements. Identify compatibility constraints and other work in progress.
- State what the player should notice, decide, risk, gain, and understand after success or failure. Describe one concrete play sequence and its feedback.
- Separate requirements, hypotheses, and starting balance values. Ask only about consequential intent or tradeoffs that the project cannot answer; record chosen defaults.

## Make a testable specification

Use [feature-brief.md](assets/feature-brief.md) as a starting point, omitting irrelevant sections. Connect behavior to the player experience, then define the minimum interfaces, ownership, data flow, compatibility work, failure behavior, and acceptance scenarios needed to implement it.

- Identify the riskiest assumption and the smallest playable prototype that can disprove it. Use [prototype-playtest.md](assets/prototype-playtest.md) to distinguish automated evidence from observations about fun, clarity, and pacing.
- Put frequently changed balance values in the project's existing editable data workflow, with units and useful validation. Specify how changes reach a fresh test session and how reproducible runs preserve their configuration.
- Separate authoritative gameplay state from presentation. An animation or effect should not silently change collision, resource spending, or command timing unless the design explicitly owns that behavior.
- Make timing and commitment legible. Specify the player's opportunity, the cost of commitment, and the recovery or relief that follows pressure where those concepts apply.

## Use lessons without copying recipes

Consult only relevant entries in [sakurai-lessons.md](references/sakurai-lessons.md). Each entry separates a timestamped source paraphrase from a possible application. Cite the lesson when it materially changes a decision, and explain why it fits this game. Do not treat a presentation example as a universal rule or attribute invented mechanics or numbers to Sakurai.

When another lesson is needed, inspect that source and add a short, timestamped paraphrase with language and retrieval limitations. Do not ingest the entire channel into every feature or store full transcripts here. If evidence cannot be retrieved, label the reference unverified instead of inventing timestamps or quotations.

## Track temporary work and revise deliberately

- Use [placeholder-register.md](assets/placeholder-register.md) for temporary art, audio, feedback, tuning, UI, or simulated systems. Record the purpose, limitation, replacement trigger, and observable completion criteria. A placeholder may stay when it already satisfies the intended experience.
- Before changing a known spec, identify affected code, data, saves/replays, design, art, animation, sound, tests, and downstream work. Report discovered problems early; compare immediate and later consequences before committing to a correction.
- Record playtest conditions, observations, decision, and the next verification step. Update the current specification rather than leaving conflicting instructions scattered across notes.
- Finish with concrete acceptance evidence and remaining uncertainties. Do not mark the prototype ready for broader content solely because it compiles or scripted tests pass.

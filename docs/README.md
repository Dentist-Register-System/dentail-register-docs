# Design Docs — Specs & Plans

This directory is the canonical home for engineering **specs/designs** and **implementation
plans** for the Register System. We practice **spec-driven development**: the design is
written here and reviewed *before* any code is written, then drives the implementation.

## Layout

| Folder | Holds | Produced by | Answers |
|---|---|---|---|
| `specs/` | Design specs (one per feature/sub-project) | brainstorming, before coding | *why* and *what* |
| `plans/` | Step-by-step implementation plans | planning, after the spec is approved | *how* |

## Why this exists

- **Durable reference.** A focused design doc beats re-deriving intent from thousands of
  lines of code or chat history. Future work (human or AI) starts from the doc.
- **Cheap review gate.** Fixing a design in a doc is far cheaper than after it ships.
- **Living history.** This repo holds the *why*; the code repos (`dentist-registry-backend`,
  `dentist-registry-frontend`) hold the *what*.

## Conventions

- Filenames: `YYYY-MM-DD-<topic>-design.md` (specs) and `YYYY-MM-DD-<topic>-plan.md` (plans).
- One spec per feature/sub-project; a spec is approved (reviewed via PR) before its plan.
- The business source of truth remains the top-level docs (`PRD/`, `Entities/`, `Workflows/`,
  `Rules/`, `tech stack/`, `testing/`). Specs here translate that into implementation intent
  and must not contradict the Golden Rules without an explicit, recorded decision.

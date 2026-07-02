# Multi-Slot Booking — Frontend Plan

**Date:** 2026-07-02
**Design:** `docs/specs/2026-07-02-multi-slot-booking-design.md`
**Wing:** Frontend — ships **after** the backend wing is live (Golden Rule 19). Additive-safe with the shipped BE either way.
**Doctrine:** Sentinel Rules 1/5/6 (FE is a messenger; PDP/PEP) · Golden §16 (i18n), §17–18 (design system, wizards) · `Rules/frontend-handbook.md` · PERMANENT UI rule — this feature runs through **/impeccable**.
**Reference:** the approved interactive mockup (real tokens + real `SlotChip`/`BookAppointmentFlow`, light + dark).
**Model (ruled):** runs extend across any contiguous slots **with room** (no cap); the engine decides bookability; edit-length + cancel-whole-run supported; both workflows.
**Prereq:** BE PRs 1–6 merged + deployed; `end_datetime` accepted on create; `PATCH …/appointments/{id}` for edit; overlap occupancy live.

## Guardrails (every PR)
- **The FE decides nothing.** Building a run is UX over engine-provided slot facts; **bookability is the engine's** — submit `{start,end}`, render the returned `Decision.reason`. No `state==='available' && adjacent`, no capacity math, no length check in any component.
- Design-system only — real tokens/components, no per-page CSS; i18n `t()` for all copy; both themes AA; `prefers-reduced-motion` honored.
- Every touched file carries the Sentinel header.

---

## PR 1 — Read layer: run submission + edit (no visible UI yet)
- Scheduling API client + hooks: allow `useCreateRequest` to submit `end_datetime`; add an edit-length mutation (`PATCH …/appointments/{id}`).
- Map new denial codes → `t("apiErrors.run_not_contiguous")` (+ existing `slot_full`, `slot_not_available`).
- **Acceptance:** typecheck green; single-slot submit unchanged; new i18n keys in all locales (i18n-parity guard green).

## PR 2 — Wizard Time step: contiguous multi-select (through /impeccable)
- `book-appointment-flow.tsx :SlotStep`: run state (a contiguous index range) — pure presentation over `slotState`. Chip states from the mockup: **selected** (violet), **Add next** (violet ring + `+`, immediate neighbours with room), **dimmed** (out of reach), **merged block** (flattened interior corners). Existing tokens only. **No length cap** — extend across contiguous slots-with-room until a `full`/`blocked`/`past` slot breaks the run.
- Run summary (`09:00–10:30 · 90 min · 3 slots`) + **Clear**; Review → Time updates live.
- **Acceptance:** matches the signed-off mockup in light + dark; keyboard + `aria` on the grid; FE sentinel guard green (no decision in the component).

## PR 3 — Submit, edit-length, confirm, error/success
- Confirm submits `{ start_datetime, end_datetime }`; on deny render `Decision.reason` inline; on allow the success card shows the run span.
- **Edit length:** from the appointment's actions (design A1), open the run selector pre-loaded at the current span; submit the edit mutation; render the result. **Cancel** frees the whole run (existing cancel action, span-aware copy).
- Edge/empty/loading + the "just taken" race (re-fetch slots, keep the wizard open).
- **Acceptance:** create + edit-length + cancel all covered in both workflows; copy via `t()`; a denied run never leaves the user stuck.

## PR 4 — FE sentinel guard extension + Playwright e2e
- Extend the FE sentinel guard to fail CI on client-side scheduling decisions (run validity/capacity/occupancy in components).
- Playwright (isolated stack): build a run → confirm → assert success + Review span; a run blocked by `Lunch` refused; a run into a full slot refused; **edit-extend, edit-shrink, cancel-whole-run**; single-slot still works; light/dark. Inject-bug proof per the bulletproof-journey model.
- **Acceptance:** guard green with teeth; e2e green locally; single-slot journeys unregressed.

---

## Deploy note
FE deploys **after** BE is verified live. Manual BE→FE order; after merge, ask "release? major/minor?" per the release model. Playwright is the local gate; beta verification is manual.

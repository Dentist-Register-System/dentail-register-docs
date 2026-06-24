# My Schedule — Availability-Submission Redesign — Design Spec (#129)

**Status:** Approved in brainstorm (2026-06-24). Issue **#129** (relates to epic **#9** Scheduling engine; builds on **#43** SP3.1 availability/slots and **#107** availability authz). **Frontend-led; no database/model change** (one small *optional* backend API addition — see §6). Register Design System (Rule 17.0), i18n-first. Directional mockups: `Mockups/schedule_main_mockup.png`, `Mockups/schedule_edit_mockup.png` (general direction only — refreshed mockups to follow; dev fine-tunes visuals at build with render-on-:8753 sign-off).

**Type:** Rebuild the `/my-schedule` screen from a functional CRUD-style availability editor into an **availability-submission tool** a non-tech-savvy dentist can use in ~5 minutes on a Sunday evening.

---

## 1. Goal

*"On a Sunday evening, in ~5 minutes, a non-techy dentist tells the system when she's free — without facing a CRUD spaceship."*

The current screen is design-system-clean in code but is a flat add/remove editor built before these mockups; it confuses even expert users. This redesign reorganises it around the real job: **set your usual week once, then tweak exceptions per week.**

## 2. Scope decisions (locked in brainstorm 2026-06-24)

1. **Model = "Usual week + exceptions"** (set once, repeats; tweak per week). Maps **1:1** onto the existing engine — **no model change**:
   - **Usual week** → `availability_window` `kind=recurring` (per weekday).
   - **One-off day** (extra hours a specific date) → `availability_window` `kind=one_off`.
   - **Time off** (day/range off) → `availability_block` (full-day or partial).
   - **Slot preview** → existing `compute_slots` (virtual; nothing persisted).
2. **"Add Slots / Add More Slots" = "Edit availability."** Slots are **never** created directly (they're computed). The slot grid is a **read-only preview** of what availability produces; any "add" affordance opens the Edit Availability modal.
3. **Multi-day selection is required** (current screen lacks it): the editor lets the user **apply the same hours to several days at once**, plus per-day fine-tuning and **split shifts** (two ranges in a day).
4. **No "Break Time" concept.** A break is just the gap between two windows on a day (a split shift). The mockup's break row is dropped.
5. **Slot duration = clinic-wide setting**, shown **read-only** on the schedule (from `clinic_settings.default_slot_size_minutes`, default 30). Not per-doctor. *(Flagged follow-up, separate tiny issue: add a slot-duration control to Settings → Scheduling — the field is PATCHable today but has no UI.)*
6. **Live edits, gated by a confirmation-preview card.** No draft/publish state machine. Hitting **Submit** in the modal opens a **confirmation-preview card** summarising the resulting week + the changes, with **Keep editing** / **Submit**; on Submit the changes apply (to future appointments) and a **success card** confirms. (Honors Golden Rules §18.5 / #60 / #61.)
7. **Cross-screen reuse:** the same components power `/my-schedule` (self), `/clinic-schedules` (owner/assistant pick a doctor), `/doctors/[id]`. Editing gated by **#107 availability authz** (owner any · doctor own · assistant iff `allow_staff_manage_availability`); the Edit button is hidden/disabled otherwise.
8. **Out of scope (noted, not precluded):** multi-clinic doctor switcher (later); calendar grid view; per-doctor slot length; explicit break concept; draft/publish workflow.

## Mockup direction — element-by-element source map (BUILD TO THIS)

Two candidate mockups were produced; we take a **hybrid**. **Read this before building — do not pick one mockup wholesale.**

- **Option B** = `Mockups/mockups_recos_availability.png` — the **frame**: main screen + empty states. Vertical day list, clean, plain-language, mobile-first. **This is the base.**
- **Option A** = `Mockups/mockup_recos_availability_slot_view_top.png` — the **editor**: its Edit-Availability modal + "Review changes" card. We take **only** the modal/review flow from A.

### Take from **Option B** (base — main screen, empty states)
1. **Overall frame & layout.** AppShell + `PageContainer`/`PageHeader`. Title "My Schedule" + subtitle "Manage your availability and view your appointment slots." Three stacked cards in B's order: **Your week → Appointment slots (preview) → Quick actions.** On desktop, top row is two columns (left: "Your week"; right: stacked "Upcoming one-off days" + "Time off"); slots + quick-actions full-width below. Mobile = B's single-column stack (B's mobile is the reference for breakpoints).
2. **Card 1 "Your week" — use B's VERTICAL LIST, not A's grid.** One row per day Mon→Sun: `Day · time range(s) · small status dot`; non-working days show **"Off"**. Split shifts render both ranges on the day's row (e.g. "10:00 AM–1:00 PM, 2:00 PM–5:00 PM"). Top-right **"Edit availability"** button (pencil). Subtitle "Your usual weekly availability."
3. **One-off days + Time off strips (B).** Two compact cards: **"Upcoming one-off days"** (badge "Upcoming N" + "View all") showing next entries as `date · extra hours`; **"Time off"** (badge + "View all") showing `date/range · reason · full/partial`.
4. **Card 2 "Appointment slots (preview)" (B).** Subtitle "Preview of availability (30-min slots)." A **Sun–Sat day selector** with the selected day in primary + a **week-range pill** ("19 – 25 May") with ‹ › steppers. Selected day shows `Monday, 20 May · Total slots: 6` + a **read-only** slot-chip grid. **Info row (B's exact wording):** "Slot duration: 30 minutes" · "Working hours: 10:00 AM–1:00 PM".
5. **Card 3 "Quick actions" — B's THREE actions only**, each with a description line: **Set weekly hours** / "Define your usual availability" · **Add one-off day** / "Add extra hours for a specific date" · **Add time off** / "Mark a day or range as unavailable". Each opens the Edit modal on the matching tab.
6. **Empty / first-run states (B).** Use B's empty states in both themes: the main-screen **"Set your availability"** illustration + **"Set my availability"** CTA (shown when no usual week), and the slots-card **"Your slots will appear here"** placeholder until availability exists.

### Take from **Option A** (editor — adopt these wholesale)
7. **Edit Availability modal — A's 3-tab modal/bottom-sheet.**
   - **Usual week tab (A):** per-day rows Mon→Sun, each = **toggle (work this day?) + start–end time + "+" to add a second range (split shift)**; disabled days greyed. Bottom: **"Apply to several days"** affordance (set hours for multiple selected days at once). Info note: "Changes apply to future appointments; existing ones are unaffected."
   - **One-off days tab (A):** header "Add extra hours on a specific date"; list of upcoming one-off entries with edit/delete; **"+ Add one-off day"**.
   - **Time off tab (A):** header "Mark dates or ranges when you're not available"; list with edit/delete; full-day **or** partial; optional reason ("Vacation"); **"+ Add time off"**.
8. **Confirmation / "Review changes" card — A's exact pattern.** On **Submit**: a card titled "Review changes" → "Here's how your schedule will look from next week" → a **mini week preview** (7 days with times + "Off") + the diff → actions **"Keep editing"** (secondary) / **"Confirm & save"** (primary). Then a success state. (This is our confirmation-preview tenet — Golden Rule 18.5 / #60 / #61.)

### DROP entirely (do NOT build — mostly from A)
- ❌ **A's 7-column "Your week" grid** and its **"1 window" / "Working windows"** labels. **Never expose the word "window"** to the user (internal term only). Use B's list + "Working hours".
- ❌ **A's "View full calendar"** quick action — there is **no full-calendar feature**; slots are a preview only.
- ❌ **A's Home screen** ("Good morning, Dr. Sayali" + **AI Brief** + stat tiles) — that's the Home screen, not My Schedule; the AI brief (#64) is **deferred**. Out of scope here.
- ❌ **A's "Why am I seeing this?"** link — drop, or replace with a single muted line "These slots come from your availability." No jargon.
- ❌ A's multiple decorative per-day colors — use one calm accent (avoid colour-as-meaning; a11y).

### Cross-cutting (both)
Soft Purple (light) / Dark Purple (dark), **both themes**; **mobile-first** (B's mobile is the reference); semantic tokens only; touch targets ≥44px; i18n en+hi parity; **render-on-:8753 + user sign-off before building**.

**One-line summary for the dev:** *Build B's main screen + empty states; drop into it A's Edit-Availability modal and "Review changes / Confirm & save" card; never show the word "window," no "View full calendar," no AI-brief tiles.*

## 3. Screen information architecture — `/my-schedule`

`PageContainer` + `PageHeader` ("My Schedule" / "Manage your availability and appointment slots"), three stacked cards:

### Card 1 — Your week (availability summary, read-only) + "Edit availability"
- **Usual week at a glance:** working days with times, e.g. "Mon 10:00 AM–1:00 PM · Tue 5:00–8:00 PM · Wed 10:00 AM–1:00 PM · Thu 5:00–8:00 PM · Fri 10:00 AM–1:00 PM". Off days shown muted or omitted. Split shifts shown as "10:00–1:00, 2:00–5:00".
- **Two compact strips:** **Upcoming one-off days** (e.g. "Sat 28 Jun · 10:00 AM–1:00 PM") and **Time off** (e.g. "Thu 26 Jun · off", "30 Jun–2 Jul · Vacation"), each with an `Upcoming` badge when relevant and a "View all →" link.
- **"Edit availability"** button → opens the modal (§4). Visible only to permitted editors (§2.7).
- **First-run empty state:** when the doctor has no usual week, replace the summary with a friendly prompt + primary CTA "Set your weekly availability" → modal on the Usual-week tab.

### Card 2 — Appointment slots (read-only preview)
- **Week selector** (Sun–Sat) + a week-range pill with ‹ › steppers (bounded to the engine's 62-day range).
- **Selected day:** the computed slot chips (e.g. "09:00–09:30") with a **"Total slots: N"** label and an `Available`/`Day off` state. Chips are **read-only here** (booking lives elsewhere).
- **Info area (read-only context):** **Slot duration** (clinic setting) · **Working hours** (that day's window(s)). *No break row.*
- Any "Add / Add more" affordance → opens **Edit availability** (never a slot builder).

### Card 3 — Quick actions
- **Set weekly hours · Add one-off day · Add time off** → open the modal on the matching tab.

## 4. Edit Availability — modal, three tabs

A modal/sheet (reuse the `sheet`/`Dialog` primitive), plain language throughout (never expose "window"/"recurring"):

### Tab A — Usual week (the hero)
- A **per-day list** (Mon–Sun). Each day row: a **toggle** "work this day?", a **time range** (start–end), and a **"+"** to add a second range (split shift). Disabled rows are greyed.
- **"Apply to several days at once":** select multiple days + set one time range + apply (so "Mon/Wed/Fri 10–1" is a single action). Per-day edits still allow the mixed pattern ("Tue/Thu 5–8").
- **Info callout:** "Changes apply to future appointments. Existing appointments are not affected."

### Tab B — One-off days
- Add **extra hours for a specific date** (date picker + time range, additive). Lists upcoming one-off days with remove.

### Tab C — Time off
- Mark a **date or range off** (full-day, or partial via a time range), optional **reason** ("Vacation"). Lists upcoming time off with remove. (Partial-day time off is newly surfaced in the UI — the backend already supports it.)

### Submit flow (all tabs)
- Footer: **Cancel** · **Submit** (label e.g. "Review changes"). **Submit** → **Confirmation-preview card** (§5).

## 5. Confirmation-preview card + success
- On Submit, show a **preview card** summarising **the resulting week** (final usual week + this week's one-off additions + time off) and **what changed** (added/removed). Actions: **Keep editing** (returns to the modal, no changes applied) · **Submit** (applies).
- On Submit → apply changes (§6), close, show a **success card** ("Your availability is updated").
- Must-acknowledge; no silent close. Conveys the "I've set my week" moment without a draft/publish state.

## 6. Data & backend

**No schema/model change.** Reuses `availability_window` (recurring + one_off), `availability_block`, `compute_slots`, and `clinic_settings.default_slot_size_minutes`. Existing endpoints (per `src/features/scheduling/api.ts`): `GET/POST/DELETE …/availability`, `…/availability/blocks`, `GET …/slots?from&to`, plus `clinic_settings` read.

**One small *recommended* backend addition (API only, no model change): a transactional "apply availability" endpoint** so the confirmation-card **Submit applies the whole week atomically** (the usual-week diff + one-off + time-off changes in a single transaction). Without it, the FE must orchestrate multiple create/delete calls and risks a half-applied week if one fails mid-way.
- **Recommended:** `PUT /api/v1/clinics/{id}/doctors/{doctorId}/availability/weekly` (and/or a batch apply) accepting the desired set, computing the diff vs current `active` recurring windows, and applying create/soft-delete in one transaction.
- **Fallback (no backend work):** FE computes the diff and issues the existing per-window create/delete calls sequentially; on partial failure, surface an error and re-fetch. (Acceptable for V1 but not atomic — decide at implementation.)

Slot duration is **read-only** on this screen (display only). *(Separate tiny follow-up issue: expose a slot-duration control in Settings → Scheduling.)*

## 7. Frontend

Rebuild composition; reuse `components/ui/*`, `components/layout/*`, semantic tokens — **no per-page CSS, no new visual styles**.
- `src/app/my-schedule/page.tsx` → the three-card layout (replaces the current `DoctorScheduleView` arrangement).
- New/reworked components under `src/features/scheduling/`:
  - `availability-summary-card.tsx` (Card 1, read-only summary + strips + empty state).
  - `slots-preview-card.tsx` (Card 2, week selector + computed slot grid + read-only info; reuses `useSlots`).
  - `quick-actions-card.tsx` (Card 3).
  - `edit-availability-modal.tsx` (the 3-tab editor) with `usual-week-tab.tsx`, `one-off-days-tab.tsx`, `time-off-tab.tsx`.
  - `availability-confirm-card.tsx` (§5 preview + success).
- Reuse the same cards on `/clinic-schedules` + `/doctors/[id]` (pass `doctorId` + viewer permission). Editing gated per §2.7.
- The legacy `availability-editor.tsx` inline editor is superseded by the modal; `slot-viewer.tsx` logic folds into `slots-preview-card.tsx`.

## 8. Cross-cutting
- **i18n** en+hi parity for all new copy (`schedule.*`) — gated by `tests/e2e/i18n.spec.ts`; no hardcoded strings; day/time formatting via `Intl`.
- **Rule 17.0** (semantic tokens, compose ui/layout, no per-page CSS), **both themes**, **mobile-first** (cards stack; modal full-width sheet on mobile), **WCAG AA**.
- **Render-on-:8753 + user sign-off before the dev builds** (main screen light/dark/mobile, the modal's 3 tabs, the confirm card, the empty state).

## 9. Tests
- **Unit/logic:** usual-week ↔ recurring-window mapping; multi-day apply expands to the right per-day set; split-shift produces two ranges; the diff (desired vs existing) for the apply step.
- **Component (RTL):** modal tabs; multi-day apply; confirm-preview card shows correct added/removed summary and only applies on Submit; empty state CTA.
- **e2e (Playwright, mocked API):** set a usual week (incl. the mixed Mon/Wed/Fri + Tue/Thu pattern), add a one-off day, add time off, Submit through the confirm card; slot preview reflects the new availability; edit gated correctly on `/clinic-schedules` for an assistant when `allow_staff_manage_availability` is off.
- Backend (if the apply endpoint is built): transactional apply + diff tests; authz reuse.

## 10. Scope guards / deferred
- **No backend model change**; slots stay virtual; capacity/slot-size stay clinic settings.
- **Deferred:** multi-clinic switcher; calendar grid; per-doctor slot length; explicit break; draft/publish.
- **Flagged follow-up (separate tiny issue):** slot-duration control in Settings → Scheduling.

## 11. Docs updates (this spec phase)
- **Workflows/16-doctor-availability.md** — rewritten to the "usual week + exceptions" model + the submit/confirm-card ritual + cross-screen editing.
- **PRD `PRD_v3_1_Founder_Edition.md`** — short note in the scheduling/availability section: availability is submitted as a *usual week + per-week exceptions*, edits are live but gated by a confirmation-preview card; "Add slots" = edit availability (slots are derived).
- **Entities** — no field changes. (Optional terminology bridge in `Entities/07-availability-window.md`: recurring = "usual week", one_off = "one-off day", block = "time off".)

## 12. Self-review (against the request + brainstorm)
- Availability-submission tool, ~5-min Sunday job, non-techy: §1/§3/§4. ✅
- Usual week + exceptions; maps to existing engine, no model change: §2.1/§6. ✅
- "Add slots" = edit availability; slots read-only preview: §2.2/§3 Card 2. ✅
- Multi-day select + split shifts (the explicit fix): §4 Tab A. ✅
- No break (split-shift gap); slot duration read-only clinic setting: §2.4/§2.5/§3. ✅
- Live edits + confirmation-preview card (no draft/publish): §2.6/§5. ✅
- Cross-screen reuse + #107 authz: §2.7/§7. ✅
- Mixed real schedules (Mon/Wed/Fri 10–1, Tue/Thu 5–8; consulting 1–2 hrs ad-hoc): supported by per-day + one-off, §4. ✅
- Mockups directional; dev renders + fine-tunes: Status/§8. ✅
- Placeholder scan: concrete components/endpoints/fields; the one open implementation choice (atomic apply endpoint vs FE-orchestrated) is stated with a recommendation, not a TBD. ✅

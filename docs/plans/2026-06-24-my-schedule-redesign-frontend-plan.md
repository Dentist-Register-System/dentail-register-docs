# My Schedule Redesign — Frontend Plan (#129)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Rebuild `/my-schedule` into an availability-submission tool — "usual week + exceptions" — matching the **Mockup direction** in the spec (Option B main screen + empty states; Option A Edit-availability modal + Review-changes card).

**Architecture:** Pure model helpers (windows ⇄ "usual week", multi-day apply, change summary) drive three read cards + a 3-tab Edit modal that stages changes and applies them atomically on a Review-changes confirm card. Reuses the existing scheduling data layer; the usual-week apply uses the new `PUT …/availability/weekly` (backend plan); one-off/time-off use existing create/delete.

**Tech Stack:** Next.js (App Router), React + TypeScript, TanStack Query, react-i18next, Tailwind v4 semantic tokens, base-ui primitives (`sheet`, `tabs`, `Switch`, `Dialog`), Vitest + RTL, Playwright. Spec: `docs/specs/2026-06-24-my-schedule-redesign-design.md` (read its **"Mockup direction — element-by-element source map"** before building UI). Mockups attached on issue #129.

## Global Constraints
- **Build to the spec's "Mockup direction" section:** Option B = main screen + empty states (vertical "Your week" list; "Slot duration / Working hours" info row; 3 quick actions). Option A = Edit modal (per-day toggle + time + "+" split shift + "Apply to several days"; One-off; Time off) + "Review changes → Keep editing / Confirm & save" card. **Never show the word "window"** (internal only) — use "Working hours". No "View full calendar", no AI-brief tiles, no 7-column grid.
- **Rule 17.0:** semantic tokens only; compose `src/components/ui/*` + `src/components/layout/*`; no per-page CSS / raw colours / palette utilities. Both light+dark; mobile-first (B's mobile is the breakpoint reference); WCAG AA (icon+text, ≥44px targets).
- **i18n-first:** all copy via `t()` under `schedule.*`; add to BOTH `en.json` and `hi.json` (parity gated by `tests/e2e/i18n.spec.ts`). Day/time via `Intl`.
- Weekday convention **0 = Monday … 6 = Sunday**.
- `npx tsc --noEmit` + `npm run build` clean before each commit. Dev FE on 3000 (never 3001/8001/5434).
- **Render on :8753 + user sign-off BEFORE building UI.** **FE PR is HELD for user QA** (do not merge until the user says "merge").

---

### Task 1: Data layer + pure model helpers

**Files:**
- Modify: `src/features/scheduling/api.ts` (add `applyWeeklyAvailability`)
- Modify: `src/features/scheduling/hooks.ts` (add `useApplyWeekly`)
- Create: `src/features/scheduling/availability-model.ts`
- Test: `src/features/scheduling/__tests__/availability-model.test.ts`

**Interfaces:**
- Produces:
  - `applyWeeklyAvailability(clinicId, doctorId, windows: WeeklyWindowItem[]): Promise<AvailabilityWindow[]>` → `PUT …/availability/weekly`.
  - `useApplyWeekly(clinicId, doctorId)` (mutation; invalidates `["windows",...]` + `["slots",...]`).
  - Types: `DayRange = { start: string; end: string }` (HH:MM); `UsualWeek = Record<number, DayRange[]>` (0..6 → ranges; missing/empty = off).
  - `windowsToUsualWeek(windows)`, `usualWeekToWindows(week)`, `setDaysRanges(week, days, ranges)`, `addRange(week, day, range)`, `summarizeWeek(week)`.

- [ ] **Step 1: Write the failing test**

```ts
// src/features/scheduling/__tests__/availability-model.test.ts
import { describe, it, expect } from "vitest";
import { windowsToUsualWeek, usualWeekToWindows, setDaysRanges } from "../availability-model";

const win = (dow: number, s: string, e: string) =>
  ({ id: `${dow}-${s}`, doctor_id: "d", kind: "recurring", day_of_week: dow,
     specific_date: null, start_time: s, end_time: e, status: "active" }) as const;

describe("availability-model", () => {
  it("groups active recurring windows into a usual week, sorted", () => {
    const wk = windowsToUsualWeek([win(2,"10:00","13:00"), win(0,"10:00","13:00"),
                                   win(0,"14:00","17:00") as never]);
    expect(wk[0]).toEqual([{ start: "10:00", end: "13:00" }, { start: "14:00", end: "17:00" }]); // Mon split
    expect(wk[2]).toEqual([{ start: "10:00", end: "13:00" }]);
    expect(wk[5]).toBeUndefined(); // Sat off
  });
  it("ignores non-active / non-recurring windows", () => {
    const wk = windowsToUsualWeek([{ ...win(0,"09:00","12:00"), status: "removed" } as never]);
    expect(wk[0]).toBeUndefined();
  });
  it("flattens a usual week to the apply payload", () => {
    const payload = usualWeekToWindows({ 0: [{ start: "10:00", end: "13:00" }], 1: [{ start: "17:00", end: "20:00" }] });
    expect(payload).toEqual([
      { day_of_week: 0, start_time: "10:00", end_time: "13:00" },
      { day_of_week: 1, start_time: "17:00", end_time: "20:00" }]);
  });
  it("applies the same range to several days (replace)", () => {
    const wk = setDaysRanges({}, [0, 2, 4], [{ start: "10:00", end: "13:00" }]);
    expect(Object.keys(wk)).toEqual(["0", "2", "4"]);
    expect(wk[2]).toEqual([{ start: "10:00", end: "13:00" }]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/scheduling/__tests__/availability-model.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement helpers + api/hook**

```ts
// src/features/scheduling/availability-model.ts
import type { AvailabilityWindow } from "./api";

export type DayRange = { start: string; end: string };
export type UsualWeek = Record<number, DayRange[]>;
export type WeeklyWindowItem = { day_of_week: number; start_time: string; end_time: string };

export const WEEKDAYS = [0, 1, 2, 3, 4, 5, 6] as const; // 0=Mon … 6=Sun

export function windowsToUsualWeek(windows: AvailabilityWindow[]): UsualWeek {
  const wk: UsualWeek = {};
  for (const w of windows) {
    if (w.kind !== "recurring" || w.status !== "active" || w.day_of_week == null) continue;
    (wk[w.day_of_week] ??= []).push({ start: w.start_time.slice(0, 5), end: w.end_time.slice(0, 5) });
  }
  for (const d of Object.keys(wk)) wk[+d].sort((a, b) => a.start.localeCompare(b.start));
  return wk;
}

export function usualWeekToWindows(week: UsualWeek): WeeklyWindowItem[] {
  const out: WeeklyWindowItem[] = [];
  for (const d of Object.keys(week)) for (const r of week[+d])
    out.push({ day_of_week: +d, start_time: r.start, end_time: r.end });
  return out.sort((a, b) => a.day_of_week - b.day_of_week || a.start_time.localeCompare(b.start_time));
}

export function setDaysRanges(week: UsualWeek, days: number[], ranges: DayRange[]): UsualWeek {
  const next = { ...week };
  for (const d of days) next[d] = ranges.map((r) => ({ ...r }));
  return next;
}

export function addRange(week: UsualWeek, day: number, range: DayRange): UsualWeek {
  return { ...week, [day]: [...(week[day] ?? []), range] };
}

export function summarizeWeek(week: UsualWeek): { day: number; ranges: DayRange[] }[] {
  return WEEKDAYS.map((d) => ({ day: d, ranges: week[d] ?? [] }));
}
```

```ts
// src/features/scheduling/api.ts  (append)
import type { WeeklyWindowItem } from "./availability-model";
export const applyWeeklyAvailability = (clinicId: string, doctorId: string, windows: WeeklyWindowItem[]) =>
  apiFetch<AvailabilityWindow[]>(`${base(clinicId, doctorId)}/weekly`, { method: "PUT", body: JSON.stringify({ windows }) });
```

```ts
// src/features/scheduling/hooks.ts  (append)
import { applyWeeklyAvailability } from "./api";
import type { WeeklyWindowItem } from "./availability-model";
export function useApplyWeekly(clinicId: string, doctorId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (windows: WeeklyWindowItem[]) => applyWeeklyAvailability(clinicId, doctorId, windows),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["windows", clinicId, doctorId] });
      void qc.invalidateQueries({ queryKey: ["slots", clinicId, doctorId] });
    },
  });
}
```

- [ ] **Step 4: Run tests + typecheck**

Run: `npx vitest run src/features/scheduling/__tests__/availability-model.test.ts && npx tsc --noEmit`
Expected: PASS / clean.

- [ ] **Step 5: Commit**

```bash
git add src/features/scheduling/availability-model.ts src/features/scheduling/api.ts src/features/scheduling/hooks.ts src/features/scheduling/__tests__/availability-model.test.ts
git commit -m "feat(scheduling): availability model helpers + weekly apply hook (#129)"
```

---

### Task 2: i18n keys (en + hi parity)

**Files:** Modify `src/i18n/locales/en.json` + `src/i18n/locales/hi.json`.

- [ ] **Step 1: Add `schedule.*` to en.json** (then mirror in hi.json with translations)

```json
"schedule": {
  "title": "My Schedule",
  "subtitle": "Manage your availability and view your appointment slots.",
  "yourWeek": { "title": "Your week", "subtitle": "Your usual weekly availability.", "edit": "Edit availability", "off": "Off" },
  "oneOff": { "title": "Upcoming one-off days", "viewAll": "View all", "badge": "Upcoming {{count}}" },
  "timeOff": { "title": "Time off", "viewAll": "View all", "fullDay": "Full day off", "vacation": "Vacation" },
  "slots": { "title": "Appointment slots", "subtitle": "Preview of availability (30-min slots).", "total": "Total slots: {{count}}", "duration": "Slot duration: {{minutes}} minutes", "workingHours": "Working hours: {{range}}", "dayOff": "Day off", "hint": "These slots come from your availability." },
  "quick": { "title": "Quick actions",
    "weekly": "Set weekly hours", "weeklyDesc": "Define your usual availability",
    "oneOff": "Add one-off day", "oneOffDesc": "Add extra hours for a specific date",
    "timeOff": "Add time off", "timeOffDesc": "Mark a day or range as unavailable" },
  "empty": { "title": "Set your availability", "body": "Add your weekly hours, one-off days and time off so patients can book with you.", "cta": "Set my availability", "slotsTitle": "Your slots will appear here", "slotsBody": "Add your availability to see your appointment slots preview." },
  "edit": { "title": "Edit availability", "tabs": { "usual": "Usual week", "oneOff": "One-off days", "timeOff": "Time off" },
    "usualSubtitle": "Set your regular weekly hours.", "workThisDay": "Work this day", "addRange": "Add another time range",
    "applyToDays": "Apply to several days", "futureNote": "Changes apply to future appointments; existing ones are unaffected.",
    "oneOffSubtitle": "Add extra hours on a specific date.", "addOneOff": "Add one-off day",
    "timeOffSubtitle": "Mark dates or ranges when you're not available.", "addTimeOff": "Add time off", "reason": "Reason (optional)" },
  "review": { "title": "Review changes", "lead": "Here's how your schedule will look from next week.", "keepEditing": "Keep editing", "confirm": "Confirm & save", "success": "Your availability is updated." }
}
```

- [ ] **Step 2: Mirror keys in hi.json** (same structure, Hindi values).

- [ ] **Step 3: Verify parity + commit**

Run: `npx playwright test tests/e2e/i18n.spec.ts` → Expected PASS.
```bash
git add src/i18n/locales/en.json src/i18n/locales/hi.json
git commit -m "i18n(schedule): My Schedule redesign strings en+hi (#129)"
```

---

### Task 3: Availability summary card (Card 1) + empty state

**Files:** Create `src/features/scheduling/availability-summary-card.tsx`; Test `src/features/scheduling/__tests__/availability-summary-card.test.tsx`.

**Interfaces:**
- Consumes: `useWindows`, `useBlocks` (hooks), `windowsToUsualWeek`, `summarizeWeek` (Task 1).
- Props: `{ clinicId; doctorId; canEdit: boolean; onEdit: (tab?: "usual"|"oneOff"|"timeOff") => void }`.
- Produces: default-export `AvailabilitySummaryCard`.

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/scheduling/__tests__/availability-summary-card.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, it, expect, vi } from "vitest";
import AvailabilitySummaryCard from "../availability-summary-card";

vi.mock("../hooks", () => ({
  useWindows: () => ({ data: [
    { id: "1", kind: "recurring", status: "active", day_of_week: 0, start_time: "10:00", end_time: "13:00", specific_date: null, doctor_id: "d" }] }),
  useBlocks: () => ({ data: [] }),
}));

it("renders the usual week as a vertical list with Off days", () => {
  render(<AvailabilitySummaryCard clinicId="c" doctorId="d" canEdit onEdit={() => {}} />);
  expect(screen.getByTestId("your-week")).toBeInTheDocument();
  expect(screen.getByTestId("week-row-0")).toHaveTextContent(/10:00/);
  expect(screen.getByTestId("week-row-5")).toHaveTextContent(/off/i); // Saturday off
});

it("shows empty-state CTA when no usual week", () => {
  // override mock: useWindows returns []
});
```

- [ ] **Step 2–4:** Run (fail) → implement → run (pass). Implement `AvailabilitySummaryCard` composing `Card`: header (title + subtitle + an "Edit availability" `Button` shown only when `canEdit`, calling `onEdit("usual")`); body = **vertical list** `summarizeWeek(week).map(...)` → a row per day `data-testid="week-row-{day}"` showing the localized day + ranges (join split shifts) or `schedule.yourWeek.off`. Below: the **Upcoming one-off days** + **Time off** strips (derive upcoming one_off windows from `useWindows` filtered `kind==="one_off"` with future `specific_date`, and `useBlocks` future `block_date`), each with badge + "View all". **Empty state:** when the usual week is empty, render the `schedule.empty` card with a primary CTA → `onEdit("usual")`. Build to spec "Mockup direction" §Option-B items 2–3 & 6. Semantic tokens only; both themes.

- [ ] **Step 5: Commit** `feat(schedule): availability summary card + empty state (#129)`.

---

### Task 4: Slots preview card (Card 2)

**Files:** Create `src/features/scheduling/slots-preview-card.tsx`; Test `__tests__/slots-preview-card.test.tsx`.

**Interfaces:**
- Consumes: `useSlots` (from/to for the selected week), `useClinicSettings(clinicId)` (for `default_slot_size_minutes`) — *(confirm hook name in `src/features/clinic/`; it exposes `default_slot_size_minutes`)*.
- Props: `{ clinicId; doctorId }`. State: selected week (Sun–Sat) + selected day.

- [ ] **Step 1: Write the failing test**

```tsx
// renders a Sun–Sat selector, slot chips for the selected day, "Total slots: N",
// and the info row "Slot duration: 30 minutes" + "Working hours: …".
// Mock useSlots → 2 slots for Monday; assert getByText(/Total slots: 2/) and the chips render.
```

- [ ] **Step 2–4:** Implement: a **Sun–Sat day selector** (7 buttons, selected = primary) + a week-range pill with ‹ › that shifts the from/to by 7 days (bounded to the engine's 62-day window); `useSlots(clinicId, doctorId, from, to)`; group slots by date; the selected day shows chips (`{start}–{end}`, read-only) + `schedule.slots.total`; the **info row** shows `schedule.slots.duration` (from settings) + `schedule.slots.workingHours` (that day's window range, computed from the day's slots' min start / max end). Empty: `schedule.empty.slotsTitle/Body`. Build to "Mockup direction" §Option-B item 4 (no "window" jargon; no "Why am I seeing this?" — optional muted `schedule.slots.hint`). testids `slots-preview`, `slot-day-{0..6}`, `slot-chip-{time}`.

- [ ] **Step 5: Commit** `feat(schedule): appointment-slots preview card (#129)`.

---

### Task 5: Quick actions card (Card 3)

**Files:** Create `src/features/scheduling/quick-actions-card.tsx`; Test `__tests__/quick-actions-card.test.tsx`.

**Interfaces:** Props `{ canEdit: boolean; onAction: (tab: "usual"|"oneOff"|"timeOff") => void }`.

- [ ] **Steps:** TDD a card with **exactly three** actions (Set weekly hours / Add one-off day / Add time off), each label + description (`schedule.quick.*`), each calling `onAction(tab)`; hidden/disabled when `!canEdit`. **No "View full calendar".** Test: three buttons render; clicking "Set weekly hours" calls `onAction("usual")`. Commit `feat(schedule): quick actions card (#129)`.

---

### Task 6: Edit Availability modal shell + Usual-week tab

**Files:** Create `src/features/scheduling/edit-availability-modal.tsx`, `usual-week-tab.tsx`; Test `__tests__/usual-week-tab.test.tsx`.

**Interfaces:**
- Consumes: `sheet` + `tabs` + `Switch` + `Input` primitives; `windowsToUsualWeek`, `setDaysRanges`, `addRange` (Task 1).
- Modal props: `{ clinicId; doctorId; open; initialTab; onOpenChange; }`. Holds **staged** `UsualWeek` state (seeded from `useWindows`) + staged one-off/time-off lists (Task 7) and opens the Review card (Task 8) on Submit.
- Usual-week tab props: `{ week: UsualWeek; onChange: (next: UsualWeek) => void }`.

- [ ] **Step 1: Write the failing test** (usual-week tab)

```tsx
// Renders Mon–Sun rows. Toggling a day on adds a default range; entering times updates it;
// the "+" adds a second range (split shift); "Apply to several days" sets selected days to a range.
// Assert: toggle Wed → onChange called with week[2] defined; click "+" on Mon → week[0] length 2.
```

- [ ] **Step 2–4:** Implement the modal shell (`Sheet` with `Tabs` = Usual week / One-off days / Time off; footer **Cancel** + **Submit**→opens Review card). Implement `UsualWeekTab`: a row per weekday (`WEEKDAYS`, localized labels, 0=Mon) with a `Switch` ("work this day"), time `Input`s (start/end), a **"+"** (`addRange`) for split shifts, disabled rows greyed; a **"Apply to several days"** control (multi-select days + one range → `setDaysRanges`). Info note `schedule.edit.futureNote`. Plain language — never render "window". Build to "Mockup direction" §Option-A item 7 (Usual week). testids `edit-availability-modal`, `usual-week-tab`, `day-toggle-{0..6}`, `add-range-{0..6}`, `apply-to-days`.

- [ ] **Step 5: Commit** `feat(schedule): edit-availability modal + usual-week tab (#129)`.

---

### Task 7: One-off days tab + Time off tab

**Files:** Create `one-off-days-tab.tsx`, `time-off-tab.tsx`; Test `__tests__/exceptions-tabs.test.tsx`.

**Interfaces:**
- Consumes: `useWindows`/`useBlocks` (existing entries), staged add/remove lists held in the modal.
- One-off tab props: `{ existing: AvailabilityWindow[]; staged: OneOffDraft[]; onAdd; onRemove }` where `OneOffDraft = { specific_date: string; start_time: string; end_time: string }`.
- Time-off tab props: `{ existing: AvailabilityBlock[]; staged: TimeOffDraft[]; onAdd; onRemove }` where `TimeOffDraft = { block_date: string; start_time: string|null; end_time: string|null; reason: string|null }`.

- [ ] **Steps:** TDD both tabs: list existing + staged entries with delete; an add row (date + time range for one-off; date/range + full-or-partial + optional reason for time off) with `+ Add` (`schedule.edit.addOneOff` / `addTimeOff`). Full-day time off = `start_time/end_time` null. Build to "Mockup direction" §Option-A item 7 (One-off / Time off). testids `one-off-tab`, `time-off-tab`, `add-one-off`, `add-time-off`. Commit `feat(schedule): one-off + time-off tabs (#129)`.

---

### Task 8: Review-changes confirm card + apply orchestration

**Files:** Create `availability-review-card.tsx`; Modify `edit-availability-modal.tsx` (wire Submit → review → apply); Test `__tests__/availability-review-card.test.tsx`.

**Interfaces:**
- Consumes: `useApplyWeekly` (Task 1); `useCreateWindow`/`useDeleteWindow` (one-off); `useCreateBlock`/`useDeleteBlock` (time off); `usualWeekToWindows`, `summarizeWeek`.
- Review card props: `{ week: UsualWeek; oneOffAdds: OneOffDraft[]; timeOffAdds: TimeOffDraft[]; removals: {...}; onKeepEditing; onConfirm; pending: boolean }`.

- [ ] **Step 1: Write the failing test**

```tsx
// Shows the mini week preview (Mon–Sun + Off) and Keep editing / Confirm & save.
// Clicking Confirm calls onConfirm; while pending, the button is disabled.
```

- [ ] **Step 2–4:** Implement `AvailabilityReviewCard` per "Mockup direction" §Option-A item 8: title `schedule.review.title`, lead `schedule.review.lead`, a **mini week preview** (`summarizeWeek` → 7 days with ranges/Off), and **Keep editing** (secondary → `onKeepEditing`) / **Confirm & save** (primary → `onConfirm`, disabled while `pending`). Wire in the modal's `onConfirm`:
  1. `await applyWeekly.mutateAsync(usualWeekToWindows(stagedWeek))` (atomic usual week).
  2. For each staged one-off add → `createWindow({ kind: "one_off", specific_date, start_time, end_time })`; for each one-off removal → `deleteWindow(id)`.
  3. For each staged time-off add → `createBlock({ block_date, start_time, end_time, reason })`; removal → `deleteBlock(id)`.
  4. On success: close modal, show a success state (`schedule.review.success`), invalidate `windows`/`blocks`/`slots`.
  On error: surface `apiErrors.<code>` and keep the modal open. testids `availability-review-card`, `review-keep-editing`, `review-confirm`.

- [ ] **Step 5: Commit** `feat(schedule): review-changes card + apply orchestration (#129)`.

---

### Task 9: Assemble `/my-schedule`, reuse on `/clinic-schedules` + `/doctors/[id]`, e2e

**Files:** Modify `src/app/my-schedule/page.tsx`, `src/app/clinic-schedules/page.tsx`, `src/app/doctors/[id]/page.tsx`; Test `tests/e2e/my-schedule.spec.ts`.

**Interfaces:** Consumes all cards (Tasks 3–8) + `useMe` (viewer role + `doctor_id`) + `useClinicSettings` (for `allow_staff_manage_availability`).

- [ ] **Step 1:** Compose `/my-schedule`: `PageContainer` + `PageHeader` (`schedule.title`/`subtitle`); `doctorId = me.doctor_id`; `canEdit = true` (own); render `AvailabilitySummaryCard` → `SlotsPreviewCard` → `QuickActionsCard`; mount `EditAvailabilityModal` controlled by an `openTab` state set by the cards' `onEdit`/`onAction`. Layout per "Mockup direction" §Option-B item 1 (desktop two-column top row; mobile single column).
- [ ] **Step 2:** Reuse on `/clinic-schedules` (doctorId from the existing DoctorPicker; `canEdit = viewerRole==="owner" || (viewerRole==="assistant" && settings.allow_staff_manage_availability)`) and `/doctors/[id]` (doctorId from route; same `canEdit`). The legacy `availability-editor.tsx` inline editor + `slot-viewer.tsx` are removed/replaced by these cards.
- [ ] **Step 3:** e2e `tests/e2e/my-schedule.spec.ts` (mock the scheduling + settings endpoints per the repo's Playwright harness): set a usual week incl. the mixed pattern (Mon/Wed/Fri 10–1, Tue/Thu 5–8) via the modal, add a one-off day + time off, Submit → Review card → Confirm; the summary + slots preview reflect it; assistant on `/clinic-schedules` cannot edit when `allow_staff_manage_availability` is off (Edit hidden).
- [ ] **Step 4:** **Render on :8753 for sign-off** — main screen (light/dark/mobile), the 3 modal tabs, the Review card, and both empty states. **Get user sign-off before considering done.**
- [ ] **Step 5:** Typecheck + build + e2e, then commit `feat(schedule): assemble My Schedule redesign + cross-screen reuse (#129)`.

---

## Self-Review (plan vs spec)
- Usual-week + exceptions model, no "window" jargon → Tasks 1, 6, 7. ✅
- "Add slots" = edit availability; slots read-only preview with duration/working-hours info row → Task 4. ✅
- Multi-day apply + split shifts → Task 1 (`setDaysRanges`/`addRange`) + Task 6. ✅
- Live edits gated by Review-changes confirm card; atomic usual-week apply → Task 8 + backend plan. ✅
- 3 cards + empty states (Option B) + Edit modal & Review card (Option A) → Tasks 3–8 (all cite the "Mockup direction" section). ✅
- Cross-screen reuse + #107 authz (`canEdit`) → Task 9. ✅
- i18n en+hi, Rule 17.0, both themes, mobile-first, render-before-build, FE-held-for-QA → Global Constraints + Tasks 2, 9. ✅
- Placeholder scan: pure logic has full code/tests; UI tasks give component contracts + key tests + cite the pinned mockup section (visuals fine-tuned at render sign-off) — not placeholders. NOTE flags `useClinicSettings`/`useMe` name confirmation. ✅
- Type consistency: `UsualWeek`/`DayRange`/`WeeklyWindowItem`/`useApplyWeekly`/card prop names consistent across Tasks 1–9. ✅

## README
Update `dentist-registry-frontend/README.md` (the My Schedule redesign) within the FE PR.

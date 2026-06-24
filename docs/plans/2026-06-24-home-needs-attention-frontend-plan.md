# Home / Needs-Attention — Frontend Plan (#62)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Build the deterministic, role-scoped Home from the `home-summary` payload — the FE renders whatever the (already role/mode-filtered) endpoint returns.

**Architecture:** `useHomeSummary` fetches the role-aware summary; `HomeShell` composes cards that render conditionally on what's present in the payload (no client-side role logic). Needs-Attention rows map a stable `type` → localized label + link.

**Tech Stack:** Next.js App Router, React+TS, TanStack Query, react-i18next, Tailwind v4 tokens, Vitest+RTL, Playwright. Spec: `docs/specs/2026-06-24-home-needs-attention-design.md`. Mockups (directional) on #62.

## Global Constraints
- **FE is dumb on role/mode** — the backend returns only role-relevant data; the FE shows a card iff its data is present (e.g. render Pending Requests iff `counts.pending_requests != null`). No role branching in the FE.
- **Rule 17.0** semantic tokens; compose `components/ui/*` + layout templates; no per-page CSS. Both themes; mobile-first (cards stack); WCAG AA (status icon+text). i18n en+hi parity (gated). Friendly date/time via `Intl`.
- `npx tsc --noEmit` + `npm run build` clean per commit. **Render-on-:8753 sign-off before building. FE PR HELD for QA.**

---

### Task 1: `home-summary` api + hook + types

**Files:** Create `src/features/home/api.ts`, `src/features/home/hooks.ts`; Test `src/features/home/__tests__/api.test.ts`.

**Interfaces:** `getHomeSummary(clinicId): Promise<HomeSummary>`; `useHomeSummary(clinicId)`; types mirroring `HomeSummaryRead` (`counts`, `today_appointments`, `upcoming`, `needs_attention: { type; count?; link }[]`).

- [ ] **Step 1:** Test: `getHomeSummary("c1")` calls `apiFetch("/clinics/c1/home-summary")` and returns the payload (mock `apiFetch`).
- [ ] **Step 2–4:** Implement types + `getHomeSummary` (`apiFetch<HomeSummary>(\`/clinics/${clinicId}/home-summary\`)`) + `useHomeSummary` (`useQuery`, key `["home-summary", clinicId]`, `refetchOnWindowFocus`).
- [ ] **Step 5: Commit** `feat(home): home-summary api + hook (#62)`.

---

### Task 2: i18n keys (en + hi)

**Files:** `src/i18n/locales/en.json` + `hi.json`.

- [ ] Add `home.*`:
```json
"home": {
  "greeting": { "morning": "Good morning, {{name}} 👋", "afternoon": "Good afternoon, {{name}} 👋", "evening": "Good evening, {{name}} 👋" },
  "needs": { "title": "Needs attention", "allClear": "You're all caught up ✨",
    "requests_awaiting_approval": "{{count}} requests awaiting approval",
    "patients_missing_details": "{{count}} patients missing details",
    "clinic_profile_incomplete": "Your clinic profile is incomplete",
    "no_availability": "You haven't set your availability" },
  "stats": { "appointmentsToday": "Appointments today", "pendingRequests": "Pending requests", "patientsThisWeek": "Patients this week", "completedToday": "Completed today" },
  "today": { "title": "Today's schedule", "viewAll": "View full schedule", "empty": "No appointments today." },
  "pending": { "title": "Pending requests", "reviewAll": "Review all", "expiresIn": "Expires in {{time}}" },
  "upcoming": { "title": "Upcoming", "count": "{{count}} appointments", "viewCalendar": "View calendar" },
  "quick": { "title": "Quick actions", "newAppt": "New appointment", "newPatient": "New patient", "inviteDoctor": "Invite doctor", "inviteAssistant": "Invite assistant" }
}
```
- [ ] Mirror in `hi.json`; run i18n parity test; commit `i18n(home): deterministic Home strings en+hi (#62)`.

---

### Task 3: `NeedsAttentionCard`

**Files:** Create `src/features/home/needs-attention-card.tsx`; Test `__tests__/needs-attention-card.test.tsx`.

**Interfaces:** Props `{ items: { type: string; count?: number; link: string }[] }`.

- [ ] **Step 1:** Test: given two items, renders a row per item with the localized label (`home.needs.<type>`, count interpolated) linking to `item.link`; given `[]`, renders the `home.needs.allClear` empty state (testid `needs-all-clear`).
- [ ] **Step 2–4:** Implement a `Card` titled `home.needs.title`; map `items` → rows (icon + `t(\`home.needs.${type}\`, { count })` + chevron, wrapped in a `Link href={link}`), testid `needs-row-{type}`; empty → the all-clear state. Status by icon+text (warning token), not colour-only.
- [ ] **Step 5: Commit** `feat(home): needs-attention card (#62)`.

---

### Task 4: Stats tiles + Today's Schedule + Upcoming

**Files:** Create `src/features/home/home-stats.tsx`, `todays-schedule-card.tsx`, `upcoming-card.tsx`; Test `__tests__/home-cards.test.tsx`.

- [ ] **Step 1:** Tests: `HomeStats` renders only the tiles present in `counts` (e.g. omits Pending Requests when `pending_requests == null`); `TodaysScheduleCard` lists `today_appointments` rows (time·patient·type·doctor) or the empty state; `UpcomingCard` lists `upcoming` days with counts.
- [ ] **Step 2–4:** Implement:
  - `HomeStats({ counts })` — 2–4 tiles; render a tile only when its count is non-null (`appointments_today`, `completed_today` always; `pending_requests`/`patients_this_week` conditionally). Friendly numbers.
  - `TodaysScheduleCard({ items })` — rows `{Intl time} · {patient_name} · {type} · {doctor_name}`; "View full schedule →" → `/my-schedule` (or `/clinic-schedules`); empty `home.today.empty`.
  - `UpcomingCard({ items })` — per-day `{date} · {count} appointments` + doctor initials avatars.
  - Compose `Card`/`components/ui/*`; testids `home-stats`, `stat-{key}`, `todays-schedule`, `upcoming`.
- [ ] **Step 5: Commit** `feat(home): stats + today's-schedule + upcoming cards (#62)`.

---

### Task 5: Quick Actions + assemble `HomeShell` + e2e

**Files:** Create `src/features/home/quick-actions-card.tsx`; Modify `src/app/page.tsx`; Test `tests/e2e/home.spec.ts`.

**Interfaces:** Consumes `useHomeSummary`, `useMe` (name + role + clinicId), the #59 `BookAppointmentFlow`, invite triggers.

- [ ] **Step 1:** `QuickActionsCard` — New appointment (opens `BookAppointmentFlow` `initial={{}}`), New patient, and Invite Doctor/Assistant **only when `me.role === "owner"`**. Test: owner sees 4 actions; assistant/doctor see 2 (no invites).
- [ ] **Step 2:** Rebuild `HomeShell` (`src/app/page.tsx`): greeting (time-of-day via `Intl` + `me.name`) + date; then `NeedsAttentionCard` → `HomeStats` → `TodaysScheduleCard` → (`PendingRequestsCard` iff `counts.pending_requests != null`) → `UpcomingCard` → `QuickActionsCard`. All driven by `useHomeSummary` (loading/error states). Keep `CreateProfileBanner`/onboarding paths.
- [ ] **Step 3:** e2e `tests/e2e/home.spec.ts` (mock `home-summary`): (a) owner-multi-approval payload → needs-attention + pending requests + clinic-wide schedule + 4 quick actions; (b) consultant-doctor payload (no patient/profile needs rows, no pending tile, 2 quick actions); (c) empty needs → "all caught up"; (d) "New appointment" opens the booking flow.
- [ ] **Step 4: Render on :8753 for sign-off** — owner-solo-direct, owner-multi-approval, consultant-doctor, all-clear (light/dark/mobile). **User sign-off before done.**
- [ ] **Step 5: Commit** `feat(home): assemble deterministic role-scoped Home (#62)`.

---

## Self-Review (vs spec)
- FE renders the role/mode-filtered payload (no client role logic) → Global Constraints + Task 5. ✅
- Needs-Attention card (type→label, empty state) → Task 3. ✅
- Conditional cards/tiles (pending only in approval; invites owner-only) → Tasks 4, 5. ✅
- New Appointment → #59 flow → Task 5. ✅
- i18n/Rule 17.0/themes/a11y/render-before-build/FE-held → Global Constraints + Tasks 2, 5. ✅
- Placeholder scan: contracts + key tests + concrete keys; pure rendering driven by payload. ✅
- Type consistency: `HomeSummary`/`needs_attention` item shape/card props consistent across tasks. ✅

## README
Update `dentist-registry-frontend/README.md` (the Home) within the FE PR.

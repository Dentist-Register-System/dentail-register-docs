# Today's Schedule — Calendar-Library Rebuild — Design Spec

> **⚠️ PIVOTED DURING IMPLEMENTATION (2026-06-27).** The FullCalendar `timeGrid` approach below was built, then **abandoned** after local testing: the time-grid cramped/clipped event text (short slots can't hold a multi-line card). We pivoted to a **diary** view instead — the spacious, full-width rows from *Doctors Schedules → Doctor → Appointments*, extended clinic-wide with per-doctor colour coding, a doctor legend, an "N in parallel" grouping for concurrent appointments, a day chip, and light/dark. **The shipped design has NO FullCalendar dependency.** Sections below referring to FullCalendar / `DayCalendar` / time-grid are historical. What shipped: per-row two-line bold time range + bold duration + ● doctor + status badge; tap-through → Appointment Requests; diary on desktop AND mobile. Frontend PR: `dentist-registry-frontend` #60. Doctor colour palette (§4.1), legend (§4.4), confirmed/pending filters (§2.5), and the empty/role/stepper behaviour (§2.9) carried over unchanged.

**Status:** Approved in brainstorm (2026-06-27) after heavy interactive-mockup iteration. **Supersedes the hand-rolled grid** shipped in Phase 2 (`2026-06-27-today-schedule-design.md`, live as BE v1.3.0 / FE v1.6.0). Register Design System (Rule 17.0), i18n-first (en/hi), **light + dark**, WCAG 2.2 AA per `testing/ux-standards-runbook.md`. **Frontend-only** (the `/schedule` endpoint is reused unchanged). **No migration.**

**Requirement source:** The hand-rolled day-grid is unusable (empty doctor columns, time-gutter misalignment, brittle overlap). Owner: *"make it like Google Calendar — a real calendar, light & dark; don't write it by hand."* Brainstorm 2026-06-27.

**Type:** Replace the bespoke `DayGrid`/`DayTimeline` with an **open-source calendar library** day view; doctor = **colour** (not column).

---

## 1. Goal

> *"Owner/assistant opens Today's Schedule and sees one day timeline with every doctor's appointments + pending requests as **colour-coded** events (colour = doctor, shown in a legend). A slot with one appointment is full-width; 2/3/4 parallel appointments sit **side-by-side**. Works in **light and dark** like Google Calendar, and on **mobile** as a colour-coded agenda. Empty days show a calm frame, never a blank."*

---

## 2. Scope decisions (locked in brainstorm 2026-06-27)

1. **Doctor = colour, not column.** This eliminates the empty-doctor-column bug (a day where one doctor is busy just shows their colour; absent doctors are simply absent). A **legend** maps colour→doctor and grows 1→N as the clinic adds doctors.
2. **Desktop/tablet = a calendar-library day time-grid.** Continuous time axis over the clinic's working window; events sized by duration; **overlapping events render side-by-side** (the library does this); a **now-line** for today.
3. **Library = FullCalendar `timeGrid` (MIT).** Its core + `@fullcalendar/timegrid` + `@fullcalendar/react` are MIT. The premium `schedulerLicenseKey` is **only** for resource views — which we do **not** use (doctor is a colour). Custom `eventContent` renders our diary-style card. *(Fallback if Next/App-Router integration is painful: `react-big-calendar`, also MIT. Decided in the plan if needed.)*
3a. **Dependency (Golden Rule §3.4):** `@fullcalendar/react`, `@fullcalendar/core`, `@fullcalendar/timegrid` (+ `@fullcalendar/interaction` only if needed for clicks). Purpose: calendar day-view layout + overlap + now-line. **License: MIT** — pin exact versions and verify transitive-dep licenses are permissive (MIT/Apache/BSD/ISC) in the plan; abort & escalate if any is copyleft/commercial.
4. **Event card (custom render):** patient name · chief complaint · **● doctor name** (the legend's dot + name, in the doctor's colour) · **status badge** (Confirmed / Requested). Left-accent + soft tint in the doctor's colour. (Mockup-approved.)
5. **Status:** **colour = doctor; badge = status.** Grid/agenda show **confirmed appointments + non-expired pending requests**. Requested events get a dashed treatment + "Requested" badge; cancelled/rejected/expired stay in the **cancelled strip** (request-side), unchanged from Phase 2.
6. **Mobile = colour-coded vertical agenda** (our own component, not the library): time-ordered rows, each left-accented in the doctor's colour with **● doctor name** + status badge; parallel appts become consecutive rows under a **"HH:MM · N in parallel"** marker. Responsive switch: grid at `lg+`, agenda below.
7. **Light + dark (Rule 17.3), Google-Calendar style:** light = light surfaces; **dark = genuinely dark surfaces** (deep bg, elevated cards) — never white cards on dark. Doctor colours **brighten in dark** for AA contrast. All via tokens; the library is themed with our CSS variables.
8. **Doctor colour palette:** a NEW token-based categorical palette in `globals.css` (light + dark values, AA-contrast in both), assigned per doctor by **stable order** (doctor id / name). 1 doctor → 1 colour, up to N (define ≥8 distinct hues, then cycle).
9. **Keep from Phase 2:** the `/schedule` endpoint, the nav item + owner/assistant gating, the **day stepper** (‹ prev / next / Today ›), the **doctor-filter pills** (now filter which doctors' events show), **tap-through** (appointment→/patients, request→/requests), and the **empty-day** calm frame.
10. **Remove:** the hand-rolled `DayGrid` and the doctor-*columns* idea.

---

## 3. What exists today (reused; verified 2026-06-27)

- **`GET /api/v1/clinics/{id}/schedule?date=`** (owner+assistant) returns `{ date, working_window {start,end}, doctors:[{id,name,specialty,windows}], appointments:[confirmed], requests:[all, with expired] }`. **Sufficient — no backend change.** (`useTodaySchedule(clinicId, date)` hook exists.)
- FE `src/features/today/`: `api.ts` (types), `hooks.ts`, `page.tsx` (route + role guard + state), `today-header.tsx` (stepper + filter pills + cancelled strip), `day-grid.tsx` + `day-timeline.tsx` (**to be replaced**).
- `request-status` colour language + `Badge`; semantic tokens in `globals.css` (`:root` light / `.dark` dark / `@theme inline`).
- Nav item `today` gated owner+assistant (`app-shell.tsx`); i18n `nav.today` + `today.*` en/hi.

---

## 4. Frontend design

### 4.1 Doctor colour palette (`globals.css`)
Add a categorical palette: `--doctor-1 … --doctor-8` (+ a matching tint, e.g. `--doctor-1-bg`) under `:root` (light) and `.dark` (brightened), all WCAG-AA against their surface. Map to Tailwind via `@theme inline`. A helper `doctorColor(index)` (or by stable doctor-id order) returns the token. ≥8 hues, cycle beyond. **No per-page colours.**

### 4.2 `<DayCalendar>` (desktop, `lg+`) — FullCalendar
- `@fullcalendar/react` `<FullCalendar>` with `plugins=[timeGridPlugin]`, `initialView="timeGridDay"`, `headerToolbar={false}` (our own header drives it), `initialDate={date}`, `nowIndicator`, `slotMinTime`/`slotMaxTime` from `working_window`, `allDaySlot={false}`, `expandRows`, `height="auto"`, `slotDuration="00:30:00"`.
- **Events:** map confirmed appointments + non-expired pending requests → `{ id, start, end, backgroundColor: tint, borderColor: doctorColor, extendedProps: { patientName, complaint, doctorName, doctorColor, status, kind } }`. Filter by the active doctor-filter (`selected`). Requests with no `end` → `defaultLen` from clinic settings.
- **`eventContent`** renders the diary card: patient (bold) · complaint (muted, truncate) · a row with **dot(doctorColor)+doctorName** and the **status Badge**. Left accent = doctor colour.
- **Theme:** drive FullCalendar's CSS variables (`--fc-border-color`, `--fc-page-bg-color`, `--fc-now-indicator-color`, etc.) from our tokens in both light/dark; no FullCalendar default theme CSS leaking ERP look.
- **Click** → tap-through (appointment→`/patients`, request→`/requests`).
- Controlled by our `date` state (re-render/`gotoDate` on change); the library handles overlap-split + alignment + now-line.

### 4.3 `<DayAgenda>` (mobile, `< lg`)
Our component (evolve the current `day-timeline.tsx`): time-ordered list of the same events; each row = time · patient · complaint · **dot+doctorName** · status badge, left-accent doctor colour. Consecutive same-start events grouped under a **"HH:MM · N in parallel"** marker. Same filter + tap-through.

### 4.4 Legend
A `<DoctorLegend>` above the calendar/agenda: a chip per active doctor = **dot(doctorColor) + name**. Reuses the same colour mapping. (Doubles as the doctor filter? Keep the existing filter pills; the legend can be the pills themselves — decide in the plan, but colour the pills with the doctor dot.)

### 4.5 Page wiring (`page.tsx`)
Keep role guard + `date`/`selected` state + `useTodaySchedule`. Render `<TodayHeader>` (stepper + filter + cancelled strip) + `<DoctorLegend>` + responsive `<DayCalendar>` (`hidden lg:block`) / `<DayAgenda>` (`lg:hidden`). Empty day → calm frame with the existing empty message (not a blank).

---

## 5. Backend
**None.** The `/schedule` endpoint already returns doctors + appointments + requests + working_window. No migration. (If the plan finds a genuine gap, raise it before coding.)

---

## 6. i18n (Rule §16)
Reuse `today.*` + `requests.status.*`. Add only if needed: `today.parallel` ("{{count}} in parallel"), `today.legend` (aria). Both en + hi; no hardcoded strings; the library's own text (none visible since `headerToolbar=false`) — verify no English leaks.

---

## 7. UX-standards mapping (`testing/ux-standards-runbook.md`)
- **[AUTO] Use of colour (WCAG 1.4.1):** doctor is colour **and** name (dot+name) — never colour alone; status is badge text, not colour alone.
- **[AUTO] Contrast (1.4.3) both themes:** doctor palette + text AA in light and dark.
- **[AUTO] Target size (2.5.8 / Rule 17.4):** events/agenda rows ≥44px hit area.
- **[AUTO] Consistency (Rule 17.0):** themed via tokens; no FullCalendar default ERP styling; nav/stepper unchanged.
- **[AUTO] nav:** tap appointment→/patients, request→/requests; Today nav owner+assistant only (doctor 403/absent — unchanged).
- **[HEURISTIC]:** reads like a calm calendar (Google-Calendar reference), light & dark.

---

## 8. Testing (P0, Rule §10.1) — Playwright e2e (mocked)
- Calendar renders events for a day (desktop viewport); a **2-hour** event spans ~4× a 30-min one; a **3-way parallel** slot renders three events side-by-side (distinct x). 
- Each event shows patient + **doctor dot+name** + status badge; doctor colour applied.
- **Expired pending** does NOT render as a live event (cancelled strip only); cancelled/rejected in strip.
- Day stepper refetches; now-line present for today, absent on other days.
- Doctor filter narrows visible events.
- **Mobile viewport** → agenda renders (calendar hidden), same data, parallel marker present.
- **Dark mode:** the calendar surface uses the dark bg token (not white) — assert a dark surface/token in `.dark`.
- Access: owner/assistant see it; non-owner doctor does not.
- tap-through routes correct.

---

## 9. Out of scope / future
- **Queue** (walk-ins + waitlist + overflow) — docs #158, next.
- **Week / month views** — FullCalendar gives them ~free later; not now (day-first per the diary).
- **Inline actions / drag-create** — view + tap-through only.
- **Appointment lifecycle states** (arrived/no-show/…) — not in BE; events are confirmed-only by the endpoint contract; status display adapts when they land.

---

## 10. Verification checklist (release gate)
- [ ] FullCalendar timeGrid day renders doctor-coloured events; overlap side-by-side; now-line (today only); working-window bounds.
- [ ] Custom event card = patient · complaint · dot+doctor · status badge; left-accent doctor colour.
- [ ] Light **and** dark both correct (dark = dark surfaces, brightened doctor colours, AA contrast).
- [ ] Mobile agenda renders the same data with parallel marker.
- [ ] Doctor legend + filter; day stepper; cancelled strip; empty frame; tap-through — all working.
- [ ] Hand-rolled `DayGrid`/`DayTimeline` removed; no dead code.
- [ ] New deps MIT, versions pinned, transitive licenses verified + documented (§3.4). No migration. BE untouched.
- [ ] All strings en + hi; a11y (colour+name, AA, ≥44px) pass. FE tsc + eslint + Playwright green.

---

## 11. Docs to update
- This spec → plan (`docs/plans/2026-06-27-today-schedule-calendar-rebuild-plan.md`).
- Note in the original Phase-2 spec that the day-view implementation was superseded by this calendar rebuild.
- `register-tech-stack.md` + FE README: add FullCalendar (MIT) as a dependency.

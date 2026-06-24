# Home — Deterministic, Role-Scoped Landing — Design Spec (#62)

**Status:** Approved in brainstorm (2026-06-24). Issue **#62** (Critical). Builds on #87 (Direct vs Approval), #59 (booking + patient-completeness), #25 (invites). **Absorbs #40** (clinic-details nudge — closed). Coordinates with **#63** (missing-info aggregation) and reserves the slot for **#64** (AI brief, deferred). Frontend + **one small backend** aggregation endpoint. Register Design System (Rule 17.0), i18n-first. Directional mockup: `Mockups/home_mockup.png` is **outdated** — see §2 (no AI brief / priority / follow-ups). Refreshed mockups to follow; render-on-:8753 sign-off before build.

**Type:** Build the daily Home into a **deterministic** (no AI), **role-scoped**, **mode-adaptive** landing: each user sees their day + only the things that actually need *them*.

---

## 1. Goal
*"A non-tech-savvy dentist opens the app and instantly sees: my day, and the 1–2 things that need me — nothing irrelevant."* The Home today is near-empty (greeting + a pending-requests card). This builds the real landing — calm, glanceable, and tailored to who's looking and how the clinic runs.

## 2. Scope decisions (locked in brainstorm 2026-06-24)
1. **Deterministic** — no AI narration. The mockup's "✨ AI Brief" is **#64 (deferred)**; #62 surfaces the *same signals, computed*. A slot is reserved for #64 to narrate later.
2. **Role-scoped + mode-adaptive** — what shows depends on **role** (owner/assistant/non-owner doctor) × **scheduling mode** (`direct_booking`/`doctor_approval`) × **clinic size** (solo/multi). No dead surfaces.
3. **Dropped/deferred from the old mockup:** request **priority** High/Med/Low (no such concept — expiry countdown conveys urgency); **"patients due for follow-up"** (no follow-up substrate; SP6 deferred); **AI brief** (#64).
4. **#40 absorbed** — the "complete clinic details" nudge becomes a role-scoped Needs-Attention row (owner only), not a separate sticky banner. #40 closed.
5. **#63 coordination** — #62 delivers the **clinic-wide aggregation** of incomplete patients (owner/assistant); #63 keeps appointment-level missing-info. Shared completeness rule lives **server-side** (§6).
6. **One backend addition** — a role-aware `GET /clinics/{id}/home-summary` (clinic-wide appointment aggregation didn't exist; appointments were per-doctor only) + `is_complete` on `PatientRead`.

## 3. Role-scoping matrix (the heart of #62)

| Needs-Attention signal | Owner | Assistant | Non-owner Doctor |
|---|:--:|:--:|:--:|
| Requests awaiting approval | ✅ (clinic-wide) | ✅ *iff* `allow_staff_approval` | ✅ **own assigned only** |
| Patients missing details | ✅ | ✅ | ❌ |
| Clinic profile incomplete | ✅ | ❌ | ❌ |
| You haven't set your availability | ✅ (if owner-doctor, own) | ❌ | ✅ (own) |

Cards/tiles scope the same way: a **doctor's** "Today's Schedule" + tiles are **their own**; **owner/assistant** see **clinic-wide**. The backend returns only role-relevant data, so the FE renders whatever it's given.

## 4. Home composition (adaptive)
`PageContainer` inside `AppShell`. Cards, in order (each shown only when role/mode warrants):
- **Header** — "Good morning/afternoon/evening, {Name} 👋" (time-of-day) + today's date.
- **① Needs Attention** (hero, §5).
- **② Key numbers** — Appointments Today · **Pending Requests** *(approval mode only)* · Patients This Week *(owner/assistant)* · Completed Today. No priority.
- **③ Today's Schedule** — today's appointments (time · patient · type · doctor); doctor→own, owner/assistant→clinic-wide; "View full schedule →".
- **④ Pending Requests** *(approval mode only)* — top requests with the **"expires in 1h 24m"** countdown + "Review all →". No priority badges.
- **⑤ Upcoming** — next few days' appointment counts (+ doctor initials on multi).
- **⑥ Quick Actions** — **New Appointment** → opens the **#59 `BookAppointmentFlow`** · New Patient · Invite Doctor / Invite Assistant *(owner only)*.

## 5. Needs Attention card (deterministic)
A short, plain-English list; each row = label + count + a deep link. Rows present per the §3 matrix:
- **"{N} requests awaiting approval"** → `/requests` *(approval mode; doctor sees own count)*.
- **"{N} patients missing details"** → `/patients` *(owner/assistant; from §6 completeness)*.
- **"Clinic profile incomplete"** → `/settings` (Clinic pane) *(owner; when clinic missing key fields, e.g. address/contact)*.
- **"You haven't set your availability"** → `/my-schedule` *(a doctor with no recurring windows)*.
- **Positive empty state:** "You're all caught up ✨" when the caller's list is empty. **No AI badge.**

## 6. Backend
### 6a. `is_complete` on `PatientRead` (shared completeness — coordinates #59/#63)
- Compute server-side: **complete = name + phone AND (age or date_of_birth) AND gender**. Add `is_complete: bool` (and optional `missing_fields: list[str]`) to `PatientRead`. #59's per-patient badge consumes this (single source of truth; no FE/BE drift). *(Confirm exact patient fields.)*

### 6b. `GET /clinics/{id}/home-summary` (role-aware) — new
- **Auth:** `CurrentMembership`. The service branches on `membership.role`, `settings.scheduling_workflow`, and clinic doctor count.
- **Response `HomeSummaryRead`:**
  ```
  { date, counts: { appointments_today, completed_today, pending_requests?, patients_this_week? },
    today_appointments: [ { start_time, patient_name, type, doctor_name, doctor_id } ],
    upcoming: [ { date, count, doctor_initials: [str] } ],
    needs_attention: [ { type, count?, link } ] }   # only role-relevant rows
  ```
- **Aggregation (new):** clinic-wide appointments by date — a `list_clinic_appointments(db, clinic_id, date_from, date_to)` across all clinic doctors (today's appointments existed only per-doctor). `today_appointments`/`upcoming` are **role-scoped**: a non-owner doctor gets only their own (`doctor_id == self`); owner/assistant get clinic-wide.
- **Counts:** `appointments_today`/`completed_today` from the aggregation (by status/date); `pending_requests` from the existing request-counts (omit in direct mode); `patients_this_week` = patients created in the last 7 days (new count) *(owner/assistant only)*.
- **needs_attention:** computed per the §3 matrix — pending-approval count (role-scoped), incomplete-patient count (owner/assistant, via §6a rule), clinic-profile-incomplete (owner), no-availability (doctor). Each row carries a stable `type` + `link` target (FE localizes the label from `type`).
- **No migration** (reads only). Reuses appointments/requests/patients/clinic-settings models.
- **Tests:** role-scoping (doctor → own appts + own-approval + no patient/profile rows; assistant → clinic-wide + patient rows + no profile row; owner → all); direct mode → no `pending_requests`/no requests rows; counts correct; `is_complete` true/false cases; cross-clinic 403.

## 7. Frontend
- `src/app/page.tsx` `HomeShell` → compose the cards (replace the bare greeting + lone `PendingRequestsCard`).
- `src/features/home/` (new): `home-summary` api + `useHomeSummary(clinicId)` hook; `needs-attention-card.tsx`, `home-stats.tsx`, `todays-schedule-card.tsx`, `pending-requests-card.tsx` (reuse/extend existing), `upcoming-card.tsx`, `quick-actions-card.tsx`.
- The FE renders whatever `home-summary` returns (role/mode filtering is server-side) — keeps the FE dumb and the logic authoritative. Quick Actions' "New Appointment" opens the #59 flow; Invite actions gated to owner.
- Greeting time-of-day + date via `Intl`.

## 8. Cross-cutting
- **i18n** en+hi for all copy (`home.*`, needs-attention `type`→label map) — gated; plain language; friendly time/date via `Intl`.
- **Rule 17.0** (semantic tokens, compose `components/ui/*` + layout templates, no per-page CSS); both themes; **mobile-first** (cards stack); WCAG AA (status icon+text).
- **Render-on-:8753 + sign-off before build** (owner-solo-direct, owner-multi-approval, consultant-doctor, empty Needs-Attention — light/dark/mobile). **FE PR held for QA; backend merges on green.**

## 9. Tests
- **Backend:** §6 role-scoping + counts + `is_complete` + 403.
- **FE unit:** needs-attention row rendering from `type`/`count`/`link`; empty "all caught up" state; mode/role conditional cards driven by the (already-filtered) payload.
- **e2e (mocked):** owner-solo-direct (no pending surfaces; schedule + needs-attention + quick actions); owner-multi-approval (request queue + clinic-wide schedule); consultant doctor (own schedule + own approvals + set-availability nudge, NO patient-details/profile rows); "New Appointment" opens the booking flow.

## 10. Scope guards / deferred
- **Deterministic only** — AI brief narration is **#64** (deferred); the Needs-Attention card is its deterministic precursor.
- **No** request priority; **no** follow-up signals (no substrate).
- **#40** absorbed (closed). **#63** keeps appointment-level missing-info; #62 owns the patient aggregation + clinic-profile rows.
- Multi-clinic switching deferred.

## 11. Self-review (against the request + brainstorm)
- Deterministic, role-scoped, mode-adaptive Home: §2/§3/§4. ✅
- Needs-Attention card replaces AI brief; role-scoped signals + empty state: §5/§3. ✅
- Patients-missing-details = owner/assistant only (the user's correction): §3/§5/§6. ✅
- Backend home-summary (role-aware) + clinic-wide aggregation + `is_complete` (shared w/ #59): §6. ✅
- No priority / no follow-ups / AI deferred; #40 absorbed; #63 coordinated: §2/§10. ✅
- New Appointment opens #59; invites owner-only: §4/§7. ✅
- i18n/Rule 17.0/themes/a11y/render-before-build/FE-held: §8. ✅
- Placeholder scan: concrete endpoint/shape/components/tests; verify-NOTE on patient field names only. ✅

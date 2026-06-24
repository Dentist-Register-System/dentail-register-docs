# Doctor Availability

The doctor tells the system when she is available. The mental model is **"usual week + exceptions"** — set the normal week once, then tweak per week. Designed to be a ~5-minute Sunday-evening task for a non-tech-savvy dentist. See `docs/specs/2026-06-24-my-schedule-redesign-design.md` (#129).

## Model
- **Usual week** — the doctor's normal weekly pattern, set once and repeating. Supports **different times per day** and **split shifts** (two ranges in a day, e.g. a lunch gap). Example: Mon/Wed/Fri 10:00 AM–1:00 PM, Tue/Thu 5:00 PM–8:00 PM. *(Stored as recurring availability windows.)*
- **One-off days** — extra hours added for a specific date (additive). *(One-off availability windows.)*
- **Time off** — a day or range marked off, full-day or partial, optional reason (e.g. "Vacation"). *(Availability blocks.)*
- There is **no separate "break" concept** — a break is simply the gap between two windows on a day.
- **Slot duration** is a clinic-wide setting (read-only on the schedule); appointment **slots are derived** from availability — they are never created directly. "Add slots" means **edit availability**.

## Editing
- The doctor edits in an **Edit Availability** modal with three tabs: **Usual week**, **One-off days**, **Time off**.
- The Usual-week editor allows **applying the same hours to several days at once**, plus per-day fine-tuning and split shifts.
- **Submit is gated by a confirmation-preview card** that summarises the resulting week and the changes (Keep editing / Submit). Changes apply **live to future appointments**; **existing appointments are not affected**. A success card confirms.
- **Who may edit:** the doctor (own), the owner (any doctor), and an assistant only when `allow_staff_manage_availability` is on (see #107). The same screens serve `My Schedule` (self), `Clinic Schedules` (admin picks a doctor), and the doctor detail page.

## Interactions with other workflows
- **Vacation / time off** that impacts existing appointments triggers the **schedule change** workflow (`17-schedule-change.md`).
- **Emergency absence** is handled through assistant coordination.
- Availability is the anchor that appointment **requests → approval → appointments** book against.

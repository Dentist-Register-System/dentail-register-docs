# Entity: Availability Window

## Purpose
An Availability Window represents a block of time during which a doctor is available for scheduling.

## Why This Entity Exists
Doctors submit weekly recurring availability. The system uses these windows to generate bookable slots.

## Core Information It Holds
- Doctor
- Clinic
- Day/date
- Start time
- End time
- Recurrence pattern, V1 weekly
- Status
- Created by
- Updated by

## Relationships
- Belongs to doctor
- Belongs to clinic
- Generates slots
- May be affected by schedule change workflow

## Lifecycle / States
- Active
- Changed
- Blocked
- Removed

## Created By
Doctor in V1, **and owner/practice_manager on a doctor's behalf** (recorded SP3.1 deviation — mirrors the SP2 owner/PM rule). Assistant availability modification is not allowed (assistants are read-only for availability), except schedule-change coordination may involve assistant operationally.

## Edited By
Doctor can edit own availability; owner/practice_manager can edit any doctor's. Schedule changes affecting appointments require assistant coordination before finalizing.

## V1 Implementation Note (SP3.1)
Two window **kinds**: weekly **recurring** (`day_of_week` 0=Mon..6=Sun + time range) and **one-off** (`specific_date` + time range); one-off is **additive** to recurring. **Vacation blocks** (`availability_block_beta`) suppress slots for a date (full-day or time-range). Status = `active`/`removed` (soft-remove). Times are clinic-local (IST, single-location V1). See `docs/specs/2026-06-19-sp3-1-availability-slot-generation-design.md` (issue #43).

## Visibility
Visible to assistants and doctors.

## Deletion Behavior
Deleting/removing availability with existing appointments triggers schedule change workflow. It must not auto-cancel appointments.

## Audit Requirements
Creation, modification, removal, and blocked vacation days should be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

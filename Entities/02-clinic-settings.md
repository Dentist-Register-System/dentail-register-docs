# Entity: Clinic Settings

## Purpose
Clinic Settings store configurable behavior that affects scheduling, communication, and workflow defaults.

## Why This Entity Exists
Different clinics operate differently. Some clinics allow multiple bookings per slot, others require strict exclusivity. Some clinics want reminders, others may adjust later. These behaviors should be clinic-level settings rather than hardcoded logic.

## Core Information It Holds
- Allow Multiple Bookings Per Slot
- Max bookings per slot, default 3 when multi-booking is enabled
- Default appointment slot size, default 30 minutes
- Appointment request expiry: an integer number of minutes (default 120), or **"Never"** (stored as null — requests do not expire and remain pending until manually resolved)
- Allow staff approval: whether assistants may approve or reject appointment requests on behalf of doctors (default **off**)
- Default post-confirmation hook delay, default 5 minutes
- Reminder configuration
- WhatsApp enabled status
- Google Calendar enabled status

> Note: the clinic's **postal address** (structured fields + generated `formatted_address` + optional `google_maps_url`) lives on the **Clinic** entity (see `01-clinic.md`), **not** in Clinic Settings. Settings hold operational/behavioral configuration; the address is clinic profile data.

## Relationships
- Belongs to clinic
- Influences slots
- Influences appointment requests
- Influences hook execution
- Influences notifications

## Lifecycle / States
Settings are active as long as the clinic is active.

## Created By
System during clinic creation.

## Edited By
Clinic owner only. Settings writes (PATCH) are restricted to the owner role.

## Visibility
Readable by all active clinic members (owner, doctor, assistant) — needed for UI gating (e.g. whether to show approve/reject actions). Write access is owner-only.

## Deletion Behavior
Settings should not be independently deleted.

## Audit Requirements
Changes to settings that affect scheduling or patient communication must be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

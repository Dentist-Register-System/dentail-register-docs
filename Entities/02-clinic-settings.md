# Entity: Clinic Settings

## Purpose
Clinic Settings store configurable behavior that affects scheduling, communication, and workflow defaults.

## Why This Entity Exists
Different clinics operate differently. Some clinics allow multiple bookings per slot, others require strict exclusivity. Some clinics want reminders, others may adjust later. These behaviors should be clinic-level settings rather than hardcoded logic.

## Core Information It Holds
- Allow Multiple Bookings Per Slot
- Max bookings per slot, default 3 when multi-booking is enabled
- Default appointment slot size, default 30 minutes
- Appointment request expiry, default 120 minutes
- Default post-confirmation hook delay, default 5 minutes
- Reminder configuration
- WhatsApp enabled status
- Google Calendar enabled status

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
Clinic owner or authorized admin. Some settings may later be restricted.

## Visibility
Visible to clinic owner and possibly practice manager. Assistants and doctors may not need direct access to all settings.

## Deletion Behavior
Settings should not be independently deleted.

## Audit Requirements
Changes to settings that affect scheduling or patient communication must be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

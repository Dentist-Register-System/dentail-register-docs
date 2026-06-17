# Entity: Calendar Event

## Purpose
A Calendar Event represents the downstream Google Calendar object created from an appointment.

## Why This Entity Exists
The system is the source of truth, but Google Calendar is used by clinics operationally. The system needs to track created events and sync/delete attempts.

## Core Information It Holds
- Appointment
- External calendar ID
- External event ID
- Sync status
- Created at
- Updated at
- Last failure reason

## Relationships
- Belongs to appointment
- Created by hook engine
- Deleted/cancelled by cancellation hooks

## Lifecycle / States
- Pending Create
- Created
- Create Failed
- Pending Delete
- Deleted
- Delete Failed

## Created By
Post-confirmation hook engine.

## Edited By
System only.

## Visibility
Visible to assistants/admins when failures occur.

## Deletion Behavior
If appointment is cancelled through the system, downstream calendar event should be deleted/cancelled. Direct Google Calendar edits are ignored.

## Audit Requirements
Create/delete attempts and failures should be traceable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

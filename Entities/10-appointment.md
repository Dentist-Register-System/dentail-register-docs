# Entity: Appointment

## Purpose
An Appointment represents a scheduled or historical patient visit.

## Why This Entity Exists
Appointments are the operational source of truth for clinic visits. They drive calendars, reminders, arrival, no-show, completion, rescheduling, cancellation, patient history, and follow-up.

## Core Information It Holds
- Patient
- Doctor
- Clinic
- Date/time
- Status
- Creation source
- Requested by
- Approved by
- Created by
- Notes
- Treatment performed
- Completion details
- Reschedule linkage
- Retroactive metadata
- Cancellation metadata

## Relationships
- Belongs to clinic
- Belongs to patient
- Belongs to doctor
- May be created from appointment request
- May create/relate to follow-up
- May be linked to replacement appointment
- May have calendar event
- May have communication messages
- May have hooks
- Has audit events

## Lifecycle / States
- Confirmed
- Cancellation Requested
- Arrived
- Completed
- Cancelled
- No Show
- Rescheduled

## Created By
Appointment request approval, doctor direct booking, retroactive creation, follow-up scheduling, or reschedule replacement.

## Edited By
Assistants and doctors may edit appropriate fields with audit trail.

## Visibility
Visible to all clinic doctors and assistants.

## Deletion Behavior
Deletion is permanent if explicitly performed and confirmed, but normal workflow outcomes should use states instead of deletion.

## Audit Requirements
All state transitions and meaningful edits require audit history.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

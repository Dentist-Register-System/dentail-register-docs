# Entity: Follow Up

## Purpose
A Follow Up represents a recommended future appointment after a patient visit.

## Why This Entity Exists
Doctors and assistants need a way to record that a patient should return later. Follow-ups create appointment requests rather than confirmed appointments.

## Core Information It Holds
- Patient
- Source appointment, if easy to implement
- Recommended doctor
- Specific follow-up date
- Created by
- Notes
- Status

## Relationships
- Belongs to patient
- May belong to source appointment
- Creates appointment request
- May notify assistant if not booked

## Lifecycle / States
- Open
- Appointment Requested
- Completed/Resolved
- Missed/Overdue

## Created By
Doctor or assistant.

## Edited By
Doctor or assistant.

## Visibility
Visible to doctors and assistants.

## Deletion Behavior
Can be deleted if entered incorrectly, with confirmation.

## Audit Requirements
Creation, updates, appointment request creation, and overdue notifications should be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

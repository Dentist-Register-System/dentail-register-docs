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
Doctor in V1. Assistant availability modification is not allowed according to latest discovery, except schedule-change coordination may involve assistant operationally.

## Edited By
Doctor can edit own availability. Schedule changes affecting appointments require assistant coordination before finalizing.

## Visibility
Visible to assistants and doctors.

## Deletion Behavior
Deleting/removing availability with existing appointments triggers schedule change workflow. It must not auto-cancel appointments.

## Audit Requirements
Creation, modification, removal, and blocked vacation days should be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

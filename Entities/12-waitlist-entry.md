# Entity: Waitlist Entry

## Purpose
A Waitlist Entry represents a patient waiting for capacity on a specific doctor/date/time slot.

## Why This Entity Exists
Slots can be full but still operationally interesting. Assistants need to track patients who may be scheduled if capacity opens.

## Core Information It Holds
- Patient
- Doctor
- Slot
- Added by
- Added at
- Notes
- Status

## Relationships
- Belongs to clinic
- Belongs to patient
- Belongs to slot
- May become appointment request if assistant promotes it

## Lifecycle / States
- Waiting
- Promoted
- Removed

## Created By
Assistant.

## Edited By
Assistant.

## Visibility
Visible to assistants. Doctors do not need normal visibility unless later required.

## Deletion Behavior
Can be removed by assistant.

## Audit Requirements
Add, remove, and promote actions should be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

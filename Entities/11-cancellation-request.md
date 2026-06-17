# Entity: Cancellation Request

## Purpose
A Cancellation Request represents a doctor-initiated request to cancel an appointment that still requires assistant coordination.

## Why This Entity Exists
Doctors may need appointments cancelled, but assistants are responsible for patient communication and operational coordination. Cancellation is not complete until the assistant resolves it.

## Core Information It Holds
- Appointment
- Requested by doctor
- Requested at
- Reason
- Optional note
- Status
- Resolution details

## Relationships
- Belongs to appointment
- Belongs to doctor
- Notifies assistants
- May lead to cancellation or reschedule

## Lifecycle / States
- Pending Assistant Action
- Resolved By Cancellation
- Resolved By Reschedule
- Dismissed, if needed later

## Created By
Doctor.

## Edited By
Assistant resolves. Doctor may not directly finalize cancellation.

## Visibility
Visible to doctors and assistants.

## Deletion Behavior
Should remain as history once created.

## Audit Requirements
Creation, resolution, and linked appointment outcome must be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

# Entity: Appointment Request

## Purpose
An Appointment Request represents a proposed appointment that requires doctor approval.

## Why This Entity Exists
Normal scheduling is assistant-initiated and doctor-approved. The request preserves the coordination and approval history before an appointment becomes confirmed.

## Core Information It Holds
- Patient
- Doctor
- Slot
- Requested by
- Requested at
- Status
- Chief complaint
- Notes
- Medical history snapshot/input
- Approval/rejection details
- Expiry status: the request carries an `expires_at` timestamp, which may be **null** when the clinic's expiry setting is "Never". A null `expires_at` means the request never enters the expired state — it remains pending until manually approved, rejected, or cancelled.
- Link to created appointment if approved

## Relationships
- Belongs to clinic
- Belongs to patient
- Belongs to doctor
- References slot
- May create appointment
- May be linked to previous request or appointment during reschedule

## Lifecycle / States
- Pending
- Approved
- Rejected
- Cancelled
- Requested - Expired Approval

## Created By
Assistant during normal scheduling, or reschedule/follow-up flows.

## Edited By
Assistants may edit non-identity fields while pending. Doctor/date/time changes require new request.

## Visibility
Visible to assistants and assigned doctor. Historical requests remain visible.

## Deletion Behavior
Requests should not normally be deleted. They are historical workflow records.

## Audit Requirements
Create, edit, cancel, approve, reject, expire, re-trigger approval notification, and stale transition failures should be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

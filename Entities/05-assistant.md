# Entity: Assistant

## Purpose
An Assistant represents the operational coordinator of the clinic.

## Why This Entity Exists
Assistants manage patient calls, appointment creation, cancellations, reschedules, follow-ups, patient communication, and daily coordination. The product is assistant-first.

## Core Information It Holds
- Name
- Phone number
- Email, optional
- Role/title
- Status
- Linked user account
- Clinic membership

## Relationships
- Belongs to clinic
- Creates patients
- Creates appointment requests
- Cancels appointments
- Reschedules appointments
- Marks arrival/no-show/completion
- Receives notifications
- Appears in audit events

## Lifecycle / States
- Invited
- Active
- Inactive

## Created By
Clinic owner or authorized admin.

## Edited By
Clinic owner or authorized admin. Assistant may edit personal profile fields.

## Visibility
Visible within clinic operational history.

## Deletion Behavior
Assistants should be deactivated rather than deleted. Historical attribution remains visible.

## Audit Requirements
Actions performed by assistants must record actor and timestamp.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

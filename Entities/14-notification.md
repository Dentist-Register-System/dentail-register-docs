# Entity: Notification

## Purpose
A Notification represents an in-app item that informs a user about something requiring awareness or action.

## Why This Entity Exists
The system coordinates work through notifications to doctors and assistants. Notifications should surface operational changes without forcing unnecessary automation.

## Core Information It Holds
- Recipient
- Type
- Priority
- Title
- Body
- Related entity
- Created at
- Read/dismissed state
- Action links

## Relationships
- Belongs to user/clinic
- References appointments, requests, cancellations, waitlists, hooks, or schedule changes

## Lifecycle / States
- Unread
- Read
- Dismissed
- Actioned

## Created By
System workflows.

## Edited By
Users may mark read/dismissed. System may update actioned state.

## Visibility
Visible to intended recipient.

## Deletion Behavior
May be cleared/dismissed but should not affect underlying records.

## Audit Requirements
Actioned notifications may be auditable if they trigger workflow changes.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

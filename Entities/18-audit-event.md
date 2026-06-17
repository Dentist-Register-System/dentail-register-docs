# Entity: Audit Event

## Purpose
An Audit Event records important changes to business entities.

## Why This Entity Exists
The product allows humans to modify, override, cancel, reschedule, and retroactively enter reality. Audit history preserves who did what and when, without overbuilding compliance.

## Core Information It Holds
- Actor
- Action
- Entity type
- Entity ID
- Previous state/value
- New state/value
- Timestamp
- Reason/note where applicable

## Relationships
- References users
- References changed entities

## Lifecycle / States
Audit events are append-only.

## Created By
System.

## Edited By
Nobody. Audit events should not be edited.

## Visibility
Visible where operationally useful: appointment history, patient history, admin views.

## Deletion Behavior
Audit events may be removed only when parent data is permanently deleted under patient deletion or clinic deletion rules.

## Audit Requirements
This entity is itself the audit record.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

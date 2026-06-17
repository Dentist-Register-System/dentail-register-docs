# Entity: Slot

## Purpose
A Slot represents a discrete bookable unit generated from doctor availability.

## Why This Entity Exists
Scheduling operates on 30-minute slots. Appointment requests, appointments, waitlists, capacity, and overrides are evaluated against slots.

## Core Information It Holds
- Doctor
- Clinic
- Start time
- End time
- Generated from availability window
- Capacity
- Occupancy
- Status
- Override indicators

## Relationships
- Belongs to doctor
- Belongs to availability window
- Has appointment requests
- Has appointments
- Has waitlist entries

## Lifecycle / States
- Available
- Pending
- Full
- Capacity Exceeded
- Blocked

## Created By
System-generated from availability windows.

## Edited By
Users do not directly edit slots. They modify availability or create appointment/request records that affect slot state.

## Visibility
Visible to assistants and doctors.

## Deletion Behavior
Slots should not be independently deleted if referenced by appointments or requests.

## Audit Requirements
Capacity-affecting changes should be traceable through appointment/request events.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

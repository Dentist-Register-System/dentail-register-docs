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

## V1 Implementation Note (SP3.1 / SP3.2)
Slots are **virtual** in V1: computed on-read from availability windows minus blocks (slot size + capacity from clinic settings) — there is **no slot row** until a slot is first booked. A physical `slot_beta` row is **lazy-materialized** on first booking/request (SP3.2), at which point it carries capacity/occupancy and is the atomic-capacity lock target. SP3.1 only computes/derives slots (occupancy always 0). See `docs/specs/2026-06-19-sp3-1-availability-slot-generation-design.md` (issue #43).

## Visibility
Visible to assistants and doctors.

## Deletion Behavior
Slots should not be independently deleted if referenced by appointments or requests.

## Audit Requirements
Capacity-affecting changes should be traceable through appointment/request events.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

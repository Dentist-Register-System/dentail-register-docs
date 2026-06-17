# Entity: Doctor

## Purpose
A Doctor represents a clinical provider whose availability can be scheduled and whose approval is required for normal appointment requests.

## Why This Entity Exists
Doctors are the decision makers for whether a patient should be placed into their schedule. The system must model doctor availability, approval actions, direct bookings, overrides, and appointment history.

## Core Information It Holds
- Name
- Phone number
- Email, optional
- Specialty
- Status
- Linked user account
- Clinic membership
- Availability ownership

## Relationships
- Belongs to clinic
- May have a linked user
- Has many availability windows
- Has many slots
- Has many appointment requests
- Has many appointments
- Can approve/reject requests
- Can create direct bookings
- Can request cancellations

## Lifecycle / States
- Invited
- Active
- Inactive

## Created By
Assistant or clinic owner through invitation workflow.

## Edited By
Doctor may edit own profile. Clinic admin/assistant may manage operational doctor setup depending on permissions.

## Visibility
Doctors can view all clinic schedules and patient records in V1.

## Deletion Behavior
Doctors should be deactivated rather than deleted. Historical attribution remains visible.

## Audit Requirements
Doctor invitation, activation, deactivation, availability changes, approvals, rejections, direct bookings, and cancellation requests should be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

# Entity: Clinic

## Purpose
A Clinic represents the operational unit using the system. In V1, the clinic is assumed to be a single physical location with doctors, assistants, patients, availability, appointments, templates, notifications, and settings.

## Why This Entity Exists
The product is built around clinic-level coordination. Doctors, assistants, patients, schedules, and appointments all exist within the context of a clinic. Clinic boundaries determine visibility, permissions, settings, and operational history.

## Core Information It Holds
- Clinic name
- Clinic phone number
- Clinic WhatsApp number
- Clinic operating hours
- Clinic address, if needed
- Clinic-level configuration
- Active/inactive status

## Relationships
- Has many users
- Has many doctors
- Has many assistants
- Has many patients
- Has many availability windows
- Has many appointment requests
- Has many appointments
- Has many templates
- Has many notifications
- Has one clinic settings object

## Lifecycle / States
A clinic can be active or inactive. V1 does not require multi-branch support.

## Created By
Clinic owner or system onboarding flow.

## Edited By
Clinic owner or authorized admin role.

## Visibility
Visible to users who belong to the clinic.

## Deletion Behavior
Clinic deletion is not a normal V1 workflow. If required later, deletion must be handled carefully because it contains all operational history.

## Audit Requirements
Clinic configuration changes should be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.

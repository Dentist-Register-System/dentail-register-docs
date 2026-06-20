# Entity: Clinic

## Purpose
A Clinic represents the operational unit using the system. In V1, the clinic is assumed to be a single physical location with doctors, assistants, patients, availability, appointments, templates, notifications, and settings.

## Why This Entity Exists
The product is built around clinic-level coordination. Doctors, assistants, patients, schedules, and appointments all exist within the context of a clinic. Clinic boundaries determine visibility, permissions, settings, and operational history.

## Core Information It Holds
- Clinic name (editable from the clinic profile)
- Clinic phone number (**required** — primary contact; enforced at onboarding and in the profile)
- Clinic WhatsApp number (optional; may differ from the phone number)
- Clinic email address (`email`, optional)
- Clinic operating hours
- **Clinic address (structured, manual — V1):** `address_line_1` (required), `address_line_2`, `landmark`, `area` (required), `city` (required), `state` (required), `pin_code` (required, 6-digit Indian PIN), `google_maps_url` (optional), and a generated **`formatted_address`** string. Captured (required) during owner onboarding, editable later from the clinic profile/settings. Used later in patient WhatsApp appointment confirmations. **No maps/geocoding/3rd-party location provider in V1** (see `docs/specs/2026-06-19-clinic-address-design.md`, issue #37).
- **Address Preview & Profile Completeness (V1):** owners can preview how the clinic appears to patients (name + `formatted_address` + optional directions link) and see an informational completeness checklist (name, address, phone, WhatsApp, email). Informational only — never blocks (see `docs/specs/2026-06-19-clinic-contact-preview-completeness-design.md`, issue #39).
- Clinic-level configuration
- Default clinic language / locale (English default)
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

## Clinic Data vs. Owner/Doctor Data

Clinic data (name, phone, address, settings) is **distinct from the owner's doctor profile**. When the clinic creator is also a practicing doctor, they create a separate `doctor_beta` record for themselves as a self-service step after clinic setup. The clinic's name and phone number are **not** automatically copied into the doctor profile — the owner fills their doctor profile independently. See `Entities/04-doctor.md` and `docs/specs/2026-06-20-owner-doctor-self-profile-nav-split-design.md`.

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

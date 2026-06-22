# Workflow: Appointment Approval
## Status
Draft v1.0

## Purpose
The appointment approval workflow converts a pending appointment request into a confirmed appointment. The doctor remains the decision maker. The assistant remains the coordinator.

## Key Decisions

### Who May Approve or Reject

Access to approve/reject a pending request depends on the actor's role and the clinic's **"Allow other staff to approve appointments"** setting (Settings → Appointment Settings, default off):

| Actor | May approve/reject? |
|---|---|
| **Owner** | Always — regardless of setting |
| **Assigned doctor** | Always — their own requests only |
| **Other doctor** | Never |
| **Assistant** | Only when "Allow other staff to approve appointments" is **enabled** |

This setting is owner-controlled and applies to all future approve/reject actions. It does not grant assistants the ability to act on any other scheduling decision (capacity, invites, clinic settings).

### Approval Actions
Doctors are presented with:

- Approve
- Approve With Note
- Reject

Approve performs an immediate approval with no confirmation dialog.

### Approve With Note
The note is optional.

If supplied, the note becomes part of the appointment context and is automatically included in patient-facing appointment confirmation messages.

Example:

Appointment Notes:
Please bring previous X-rays.

### Appointment Attribution
Appointments created through approval retain both actors:

Requested By:
Assistant

Approved By:
Doctor

### Approval Failure Handling
If the request is no longer active, approval fails.

Example:

- Request cancelled
- Request expired
- Request already rejected

The doctor should see the reason and current state rather than a generic error.

### Approved Request Retention
The appointment request remains in the system.

Request:
Status = Approved

Appointment:
Status = Confirmed

The request acts as historical workflow data.

### Post Confirmation Hook Engine
Approval creates a confirmed appointment.

External actions are executed through post-confirmation hooks.

Examples:

- WhatsApp confirmation
- Google Calendar creation
- Future integrations

Default delay:

5 minutes

### Hook Rules

- Hooks execute independently.
- Hook failures do not roll back appointments.
- Hooks re-validate appointment state before execution.
- Cancelled appointments prevent pending hooks from executing.

### Approval Note Propagation

Doctor approval notes should be appended to patient confirmation messages.

### Google Calendar

Calendar updates are performed through hooks.

The scheduling system remains the source of truth.

Calendar failures never roll back appointment confirmation.

# Register System - Technology Stack Decision Record

Version: 1.0

## Purpose

This document defines the approved technology stack for V1.

Claude Code should treat these decisions as locked unless explicitly changed by the user.

The goal is consistency, maintainability, developer velocity, and low operational complexity.

---

# Architecture Overview

Frontend Repository
    ↓
Next.js + TypeScript

Backend Repository
    ↓
FastAPI + Python

Database/Auth
    ↓
Supabase

External Integrations
    ↓
WhatsApp Adapter
Google Calendar Adapter

Deployment
    ↓
Vercel (Frontend)
Render (Backend)

---

# Repository Strategy

## Decision

Use separate repositories.

### Frontend Repository

```text
register-web
```

### Backend Repository

```text
register-api
```

## Why

- Simpler deployment
- Cleaner ownership boundaries
- Easier CI/CD setup
- Easier future scaling
- Easier onboarding

Claude Code must not assume a monorepo structure.

---

# Frontend Stack

## Framework

Next.js

## Language

TypeScript

## UI

shadcn/ui

## Styling

Tailwind CSS

## Forms

React Hook Form

## Validation

Zod

## Data Fetching

TanStack Query

## State Management

Use local component state + TanStack Query.

Do not introduce Redux unless explicitly approved.

## API Communication

REST APIs only.

Do not introduce GraphQL.

---

# Backend Stack

## Framework

FastAPI

## Language

Python

## Validation

Pydantic

## ORM

SQLAlchemy 2.x

## Migrations

Alembic

## API Style

REST

## Business Logic

Business rules belong in backend services.

Do not implement critical workflow enforcement only in the frontend.

---

# Database

## Provider

Supabase

## Database

PostgreSQL

## Usage

Use Supabase for:

- PostgreSQL
- Authentication
- Storage (if needed later)

## Do Not Use

Do not place business logic in:

- Supabase Edge Functions
- Database triggers implementing business workflows

Business logic belongs in FastAPI.

---

# Authentication

## Provider

Supabase Auth

## Supported Methods

Primary:

- Phone OTP

Secondary:

- Email + Password

Future:

- Social login if explicitly requested

---

# Background Jobs and Hooks

## Decision

Database-backed hook system.

Use the Hook entity already defined in discovery.

## Initial Architecture

```text
Appointment Approved
    ↓
Hook Created
    ↓
Background Worker Polls
    ↓
Executes Side Effect
```

## Do Not Introduce Initially

- Redis
- Celery
- Kafka
- RabbitMQ

Unless a demonstrated need exists.

V1 traffic does not justify the complexity.

---

# WhatsApp Integration

## Architecture

Provider Adapter Pattern

```text
WhatsAppProvider
```

Concrete providers may include:

- Meta Cloud API
- Twilio
- Gupshup

## Decision

Provider selected later.

Claude Code should build an abstraction layer first.

---

# Google Calendar

## Provider

Official Google Calendar APIs

## Philosophy

System is source of truth.

Flow:

```text
System
    ↓
Google Calendar
```

Never:

```text
Google Calendar
    ↓
System State
```

---

# AI Layer

## Architecture

Provider abstraction.

## Default Provider

OpenAI

## Future Providers

- OpenRouter
- Anthropic
- Other LLM providers

## Rules

AI may:

- summarize
- prioritize
- generate briefs

AI may not:

- schedule appointments
- approve appointments
- reject appointments
- contact patients autonomously

---

# Testing Stack

## Backend

pytest

## Frontend

Playwright

## Requirements

Every feature requires:

- Unit tests
- Integration tests
- Relevant P0 coverage

---

# Local Development

## Frontend

```bash
npm install
npm run dev
```

Default:

```text
http://localhost:3000
```

## Backend

```bash
make install
make migrate
make run
```

Default:

```text
http://localhost:8000
```

## Optional Local Services

```bash
docker compose up -d
```

Used only for local dependencies when required.

## Preferred V1 Development Mode

Frontend: Local

Backend: Local

Supabase: Remote development project

This minimizes local infrastructure complexity.

---

# Environment Configuration

Frontend:

```env
NEXT_PUBLIC_API_BASE_URL=...
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
```

Backend:

```env
DATABASE_URL=...
SUPABASE_URL=...
SUPABASE_SERVICE_ROLE_KEY=...
OPENAI_API_KEY=...
```

Secrets must never be committed.

---

# Deployment

## Frontend

Platform:

Vercel

Reason:

- Native Next.js support
- Preview deployments
- Simple GitHub integration

## Backend

Platform:

Render

Reason:

- Simple FastAPI deployment
- Background worker support
- Managed infrastructure

## Database

Platform:

Supabase

---

# Dependency Rules

Only open-source libraries may be introduced without approval.

Preferred licenses:

- MIT
- Apache 2.0
- BSD
- ISC

Claude Code must ask before introducing:

- AGPL
- GPL
- Commercial SDKs
- Proprietary SDKs
- Paid platform dependencies

---

# Architecture Principles

1. Keep it simple.
2. Prefer modular monolith.
3. Preserve auditability.
4. Preserve history.
5. Humans decide.
6. AI advises.
7. Backend enforces business rules.
8. Test product behavior first.
9. Avoid premature complexity.
10. Ask before changing locked technology decisions.

---

# Final Instruction To Claude Code

These stack decisions are considered approved.

Claude Code may choose implementation details within these constraints, but should not replace major technologies without explicit approval from the user.

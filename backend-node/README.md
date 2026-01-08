# backend-node (Node.js API)

## Purpose

Online backend to support:

- Google login (verify Google ID token)
- Creating user record on first login
- CRUD APIs for entities
- Two-way sync APIs (`/sync/push`, `/sync/pull`)

## Planned Tech

- Node.js + TypeScript
- Express (or Fastify)
- PostgreSQL (via `pg`)

## Local Development (planned)

1. Start Postgres (see `../db/README.md`).
2. Configure env:

```bash
cp .env.example .env
```

3. Install + run:

```bash
npm install
npm run dev
```

## API Outline

- `POST /auth/google` -> verify token, create/find user, return JWT/session
- `POST /sync/push` -> accept batch outbox events
- `GET /sync/pull?cursor=<event_id>` -> return server events since cursor

See `../docs/sync/SYNC_ARCHITECTURE.md`.

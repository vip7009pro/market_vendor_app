# Monorepo Plan

This repository currently contains the Flutter mobile app.

This document defines the planned monorepo structure to add:

- Node.js backend API (online DB access + sync)
- PostgreSQL database schema + migrations
- React web frontend

## Folder Structure

- `backend-node/`
  - Node.js backend (API + auth + sync)
- `db/`
  - PostgreSQL schema/migrations + local docker compose
- `web-react/`
  - React web app (future)
- `docs/`
  - Architecture and implementation notes

## High-level Requirements

- Users login with Google. On first login, create the user record in the online DB.
- Offline-first on mobile:
  - Always write to local SQLite first.
  - When internet is available, sync to server and pull down remote changes.
- Two-way sync:
  - Push local changes (outbox) to server.
  - Pull server changes since last cursor/version.
- Reduce conflicts:
  - Prefer operation-based sync (change log) rather than full-table overwrites.
  - Use a deterministic conflict policy when concurrent updates occur.

## Next Docs

- `docs/sync/SYNC_ARCHITECTURE.md`
- `backend-node/README.md`
- `db/README.md`
- `web-react/README.md`

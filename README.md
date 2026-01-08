# market_vendor_app

This repository is evolving into a **monorepo** to support **mobile (Flutter)** + **web (React)** with an **online backend (Node.js)** and **PostgreSQL** database.

## Monorepo Structure

- `lib/`, `android/`, `ios/` (Flutter mobile app)
- `backend-node/` (Node.js API for auth + sync)
- `db/` (PostgreSQL schema + migrations + docker compose)
- `web-react/` (React web app - planned)
- `docs/` (architecture + implementation notes)

## Key Docs

- `MONOREPO_PLAN.md`
- `docs/sync/SYNC_ARCHITECTURE.md`

## Backend / DB / Web

- Backend: `backend-node/README.md`
- Database: `db/README.md`
- Web: `web-react/README.md`

## Flutter

Flutter code remains in the root as a standard Flutter project.

- Flutter docs: https://docs.flutter.dev/

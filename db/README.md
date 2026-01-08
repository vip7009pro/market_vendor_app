# db (PostgreSQL)

## Purpose

Holds the online database schema + migrations for sync.

## Local Dev (Docker)

```bash
docker compose up -d
```

Database:

- Host: `localhost`
- Port: `5432`
- User: `postgres`
- Password: `postgres`
- DB: `market_vendor`

## Migrations

- `migrations/001_init.sql` contains the initial schema.

## Notes

- Each row should include: `user_id`, `created_at`, `updated_at`, `deleted_at`.
- A `sync_events` table is used for pull-based syncing.

See `../docs/sync/SYNC_ARCHITECTURE.md`.

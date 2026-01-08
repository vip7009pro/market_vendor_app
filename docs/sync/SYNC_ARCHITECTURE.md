# Sync Architecture (Online/Offline, Mobile + Web)

## Goals

- Offline-first on mobile.
- Online DB is source of truth for cross-device/web.
- Two-way sync with minimal conflicts.
- Support future React web app using the same backend.

## Identity & Auth

- **Auth Provider**: Google Sign-In.
- **Backend verification**: validate Google ID token on backend.
- **User creation**:
  - On first successful login, backend creates `users` row.
  - `user_id` (UUID) is the stable identifier.

## Data Ownership

- **MVP decision**: 1 Google account = 1 store.
- All business data is scoped by `user_id`.

## Core Idea: Change-log (operation) based sync

Instead of syncing entire tables, we sync **changes**.

### Why

- Smaller payload.
- Enables deterministic merging.
- Supports deletions via tombstones.

## Recommended Tables/Columns (Server)

For each entity table (example `debts`):

- `id` UUID (client-generated OK)
- `user_id` UUID
- `created_at` timestamptz
- `updated_at` timestamptz
- `deleted_at` timestamptz NULL
- `updated_by_device_id` text NULL
- `row_version` bigint (server-assigned monotonically increasing per row)

And a **change log**:

### `sync_events`

- `event_id` bigserial PK
- `user_id` UUID
- `device_id` text
- `entity` text (e.g. `debts`, `customers`)
- `entity_id` UUID
- `op` text (`upsert` | `delete`)
- `payload` jsonb (for upsert)
- `client_updated_at` timestamptz
- `server_received_at` timestamptz

## Client (Mobile) Local DB

Keep your current SQLite tables, and add:

### `sync_state`

- `user_id`
- `device_id`
- `last_server_event_id` (cursor for pull)
- `last_sync_at`

### `outbox`

- `id` INTEGER PK AUTOINCREMENT
- `user_id`
- `device_id`
- `entity`
- `entity_id`
- `op` (`upsert` | `delete`)
- `payload_json`
- `client_updated_at`
- `status` (`pending` | `sent` | `error`)
- `retry_count`

## Sync Protocol

### 1) Push (client -> server)

- Client sends a batch of outbox items in order.
- Server validates ownership (`user_id` from auth token).
- Server applies each event:
  - `upsert`: merge into entity table
  - `delete`: set `deleted_at`
- Server writes a row into `sync_events` with an increasing `event_id`.

### 2) Pull (server -> client)

- Client requests: `GET /sync/pull?cursor=last_server_event_id`
- Server returns ordered events: `event_id > cursor`.
- Client applies to local DB.
- Client updates `last_server_event_id`.

### 3) When to sync

- On app start.
- On login.
- On network regained.
- Periodic background attempt (if you enable it).

## Conflict Minimization Strategy

### Primary policy: Last-write-wins (LWW) by `updated_at`

- Each upsert carries `client_updated_at`.
- Server compares with existing `updated_at`.
- If incoming is newer, accept.
- If older, ignore OR accept only if it fills missing fields.

## MVP simplification: sale items

The current Flutter SQLite schema stores `sale_items` with an auto-increment integer id.
To avoid unstable IDs across devices in MVP, the server stores **sale items as `items` JSONB** inside the `sales` table.
The web app can still render the line items.

### Stronger policy (recommended): Field-level merge using `updated_fields`

- Outbox payload can include `updated_fields: [..]`.
- Server merges only those fields.
- Reduces accidental overwrites when concurrent edits touch different fields.

### Deletions

- Use `deleted_at` tombstone.
- A delete wins over an update only if delete has newer `client_updated_at`.

## Idempotency

- Client-generated `event_uuid` can be added to outbox and server events.
- Server stores `event_uuid` with unique constraint per `(user_id, event_uuid)` to prevent duplicates.

## Future Web App

- Web app can:
  - Work online-only initially.
  - Later add offline storage (IndexedDB) + same outbox/pull logic.

## Implementation Roadmap

1. Backend auth (Google ID token verification) + `users` table.
2. Define PostgreSQL schema + migrations for core entities.
3. Build sync endpoints (`/sync/push`, `/sync/pull`).
4. Mobile: implement outbox writing on every local change.
5. Mobile: background sync runner + network detection.
6. Web: basic CRUD consuming same API.

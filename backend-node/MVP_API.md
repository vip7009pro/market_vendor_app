# MVP API Contract

## Auth

### `POST /auth/google`

Body:

```json
{
  "idToken": "<google_id_token>",
  "deviceId": "<device-id>"
}
```

Response:

```json
{
  "token": "<jwt>",
  "userId": "<uuid>"
}
```

## Sync

All sync endpoints require:

- `Authorization: Bearer <jwt>`

### `POST /sync/push`

Body:

```json
{
  "deviceId": "<device-id>",
  "events": [
    {
      "eventUuid": "<uuid>",
      "entity": "debts",
      "entityId": "<uuid>",
      "op": "upsert",
      "payload": { "...": "..." },
      "clientUpdatedAt": "2026-01-08T00:00:00.000Z"
    }
  ]
}
```

Notes:

- `eventUuid` is recommended for idempotency (client can retry safely).
- LWW is based on `clientUpdatedAt` (must be an ISO datetime string).
- Entity names should match server table names:
  - `products`, `customers`, `sales`, `debts`, `debt_payments`, `purchase_orders`, `purchase_history`, `expenses`, `employees`, `vietqr_bank_accounts`

Response:

```json
{
  "ok": true,
  "acceptedEventIds": [1,2,3]
}
```

### `GET /sync/pull?cursor=<event_id>&limit=500`

Response:

```json
{
  "cursor": 123,
  "events": [
    {
      "event_id": 124,
      "device_id": "...",
      "entity": "debts",
      "entity_id": "...",
      "op": "upsert",
      "payload": {},
      "client_updated_at": "...",
      "server_received_at": "..."
    }
  ]
}
```

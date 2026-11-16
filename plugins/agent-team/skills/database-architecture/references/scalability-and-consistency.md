# ORM Engineering, Concurrency, Reservation Leases, Outbox & Schema Evolution

Concrete production patterns for `database-architecture` Pillars 4, 7, and 8.

---

## 1. ORM Engineering: Eliminating N+1, Lazy-Load Traps & Over-Fetching

### Anti-Pattern 1: Query-in-Loop (`N+1` Waterfall)
```typescript
// DEFECT (query_in_loop_hazard): 100 order IDs = 100 sequential DB round-trips
for (const orderId of orderIds) {
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  results.push(order);
}
```

### Production Pattern: Batched `IN` Query + Explicit Read Projection (CQRS-Lite)
```typescript
// 1 round-trip + explicit column projection (no SELECT *, no deep object graph hydration)
const orders = await prisma.order.findMany({
  where: {
    tenantId,
    id: { in: orderIds },
    deletedAt: null,
  },
  select: {
    id: true,
    status: true,
    subtotalCents: true,
    taxCents: true,
    createdAt: true,
  },
});
```

### Stack-Specific Eager / Batch Loading Reference

| Stack / ORM | Forbidden Pattern | Required Batch / Projection Pattern |
|---|---|---|
| **Prisma** | `await prisma.x.findUnique()` inside `for` / `Promise.all(items.map(...))` | `findMany({ where: { id: { in: ids } }, select: { ... } })` |
| **Drizzle** | `await db.select().from(t).where(eq(t.id, x))` in loop | `db.select({ id: t.id, ... }).from(t).where(inArray(t.id, ids))` |
| **SQLAlchemy 2.0** | Accessing implicit lazy relationship `order.items` in serializer (triggers sync `DetachedInstanceError` or N+1) | `raise_on_sql` on relationship defaults + explicit `selectinload(Order.items)` or flat `select(Order.id, ...)` |
| **Django ORM** | Iterating `for o in Order.objects.all(): print(o.customer.name)` | `Order.objects.filter(...).select_related("customer").prefetch_related("items").only("id", ...)` |
| **GORM (Go)** | `for _, id := range ids { db.First(&o, id) }` | `db.Select("id", "status", "subtotal_cents").Preload("Items").Where("id IN ?", ids).Find(&orders)` |

---

## 2. Concurrency Control, Reservation Leases & Isolation Matrix

| Contention Scenario | Failure Anomaly if Unprotected | Required Mechanism | Implementation Pattern |
|---|---|---|---|
| **User editing a document / profile / order** | Lost Update (User B overwrites User A's concurrent save) | **Optimistic Concurrency Control (`version`)** | `UPDATE orders SET status = $1, version = version + 1 WHERE id = $2 AND tenant_id = $3 AND version = $4 RETURNING id, version;` (0 rows = `409 Conflict`) |
| **Wallet / ledger / quota deduction** | Negative balance under parallel requests (Read-Modify-Write race) | **Atomic Conditional Update + Ledger Entry** | `UPDATE ledger_accounts SET cached_balance_cents = cached_balance_cents - $1, version = version + 1 WHERE id = $2 AND cached_balance_cents >= $1 RETURNING cached_balance_cents;` |
| **Flash-sale inventory / event seat hold during checkout** | Overselling or permanently locked stock when users abandon checkout | **Time-Bounded Reservation Lease (`expires_at`)** | Insert `inventory_reservations(sku_id, qty, status='HELD', expires_at=now()+'10 min')` while `available_qty >= qty`; confirm on payment webhook or release expired holds. |
| **Background workers claiming jobs** | Duplicate execution or head-of-line lock contention | **Row-Level Lock with `SKIP LOCKED`** | `SELECT id, payload FROM jobs WHERE status = 'PENDING' AND run_at <= clock_timestamp() ORDER BY run_at ASC LIMIT 10 FOR UPDATE SKIP LOCKED;` |
| **Calendar / room / resource slot booking** | Double-booked overlapping intervals | **PostgreSQL Exclusion Constraint (`GiST`)** | `ALTER TABLE bookings ADD CONSTRAINT ex_bookings_no_overlap EXCLUDE USING gist (room_id WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&) WHERE (status = 'CONFIRMED');` |
| **Multi-row financial reconciliation / cap check** | Write Skew (two transactions read total < limit and both insert) | **`SERIALIZABLE` Isolation + Retry** | `BEGIN ISOLATION LEVEL SERIALIZABLE; ... COMMIT;` with exponential backoff retry on `SQLSTATE 40001`. |

### Concrete Time-Bounded Reservation Lease Schema (Tickets / Inventory / Seats)
```sql
CREATE TABLE inventory_reservations (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    tenant_id UUID NOT NULL,
    sku_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    customer_id UUID NOT NULL,
    idempotency_key TEXT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    status TEXT NOT NULL DEFAULT 'HELD'
        CHECK (status IN ('HELD', 'CONFIRMED', 'EXPIRED', 'RELEASED')),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (tenant_id, idempotency_key)
);

-- Partial index so expiration sweeps only inspect active holds
CREATE INDEX CONCURRENTLY idx_reservations_active_expiry
    ON inventory_reservations (expires_at ASC)
    WHERE status = 'HELD';
```

---

## 3. Transactional Outbox Pattern (Eliminating Dual-Write Split-Brain)

Never publish to Kafka, RabbitMQ, Redis Streams, SQS, external search indexes, or webhooks directly inside an HTTP handler without an outbox. If the DB commits and the process crashes before the broker ack, the system enters permanent split-brain.

```sql
CREATE TABLE outbox_events (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    tenant_id UUID NOT NULL,
    aggregate_type TEXT NOT NULL,
    aggregate_id UUID NOT NULL,
    event_type TEXT NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1,
    idempotency_key TEXT NOT NULL UNIQUE,
    payload JSONB NOT NULL,
    status TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'PUBLISHED', 'DEAD_LETTER')),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    published_at TIMESTAMPTZ
);

CREATE INDEX CONCURRENTLY idx_outbox_pending_poll
    ON outbox_events (next_attempt_at ASC, id ASC)
    WHERE status = 'PENDING';
```

---

## 4. Multi-Tenant Row-Level Security (RLS) & Data Privacy (PII Isolation)

### Mechanical Tenant Isolation (`ENABLE + FORCE ROW LEVEL SECURITY`)
```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_policy ON orders
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid);
```

### GDPR / Privacy Right-to-Erasure Without Corrupting Financial Ledgers
Never hard-delete financial orders or ledger entries when a user requests GDPR deletion. Separate **PII identity attributes** (`user_pii` table with `full_name`, `email`, `phone`, `encrypted_tax_id`) from **immutable financial records** (`orders`, `journal_entries` referencing opaque `user_id`). On erasure request, redact/delete the `user_pii` row while preserving accounting integrity.

---

## 5. Zero-Downtime Expand-and-Contract Evolution (SQL & Document/Event Schemas)

| Evolution Goal | Unsafe (Causes Outage / Lock / Crash) | Safe Zero-Downtime Expand-and-Contract Sequence |
|---|---|---|
| **Add an index** | `CREATE INDEX idx_... ON orders (...);` (blocks writes) | `CREATE INDEX CONCURRENTLY idx_... ON orders (...);` |
| **Add a `NOT NULL` column** | `ALTER TABLE orders ADD COLUMN phone TEXT NOT NULL;` (without default or breaking old pods) | 1. **Expand**: `ADD COLUMN phone TEXT NULL;`<br>2. **Dual-write & Batch Backfill** (`LIMIT 5000`)<br>3. **Validate**: `ADD CONSTRAINT chk_phone_nn CHECK (phone IS NOT NULL) NOT VALID;` then `VALIDATE CONSTRAINT chk_phone_nn;`<br>4. **Contract**: `ALTER COLUMN phone SET NOT NULL;` |
| **Add a Foreign Key** | `ALTER TABLE orders ADD CONSTRAINT fk_cust FOREIGN KEY ...;` (locks both tables) | 1. `CREATE INDEX CONCURRENTLY` on FK column<br>2. `ADD CONSTRAINT ... FOREIGN KEY ... NOT VALID;`<br>3. `VALIDATE CONSTRAINT ...;` |
| **Rename or Drop a column** | `RENAME COLUMN x TO y` or `DROP COLUMN x` in 1 deploy | 1. **Expand**: Add `y`, dual-write `x` & `y`, backfill `y`<br>2. **Switch reads** to `y`<br>3. **Contract** (next release): `ALTER TABLE ... DROP COLUMN x; -- expand-contract` |
| **Evolve JSONB / Document / Event payload** | Changing field shape in-place without version | Include `schema_version` on the row/event and apply lazy **upcasters** (`v1 -> v2`) at read/consume time while writing `v2`. |

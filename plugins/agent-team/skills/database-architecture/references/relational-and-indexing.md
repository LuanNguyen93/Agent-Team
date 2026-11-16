# Domain Modeling, Storage Engine Matrix, Multi-ORM Schemas & ESR Indexing

Concrete production patterns for `database-architecture` Pillars 1–6 across Relational (PostgreSQL, MySQL, SQLite), Columnar/Analytical, and major ORMs (Prisma, Drizzle, SQLAlchemy, GORM).

---

## 1. Domain Truth Patterns: Live Reference vs. Point-in-Time Snapshot vs. Immutable Ledger

### Pattern A: Live Catalog Reference + Point-in-Time Transaction Snapshot
Never rely on a bare Foreign Key to mutable master data (`products.price_cents`, `users.address`, `tax_rates.rate_bps`) to reconstruct historical orders or invoices. Freeze the point-in-time values on the transaction record at checkout:

```sql
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    tenant_id UUID NOT NULL,
    sku TEXT NOT NULL,
    name TEXT NOT NULL,
    current_price_cents BIGINT NOT NULL CHECK (current_price_cents >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (tenant_id, sku)
);

CREATE TABLE order_line_items (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    -- Optional reference to catalog product (RESTRICT delete so history remains traceable)
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    -- POINT-IN-TIME SNAPSHOTS: immutable once the order is placed!
    sku_snapshot TEXT NOT NULL,
    product_name_snapshot TEXT NOT NULL,
    unit_price_cents_at_purchase BIGINT NOT NULL CHECK (unit_price_cents_at_purchase >= 0),
    tax_rate_bps_snapshot INTEGER NOT NULL CHECK (tax_rate_bps_snapshot BETWEEN 0 AND 10000),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    line_total_cents BIGINT GENERATED ALWAYS AS (unit_price_cents_at_purchase * quantity) STORED
);
```

### Pattern B: Immutable Double-Entry Financial Ledger (Source of Truth = Facts, Balance = Projection)
For wallets, payouts, credits, or accounting, never treat an in-place `UPDATE accounts SET balance = ...` as the sole record. Store immutable double-entry postings where every journal entry sums to zero:

```sql
CREATE TABLE ledger_accounts (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    tenant_id UUID NOT NULL,
    code TEXT NOT NULL,
    currency CHAR(3) NOT NULL,
    -- Materialized projection updated in the same ACID transaction as ledger_postings insert
    cached_balance_cents BIGINT NOT NULL DEFAULT 0,
    version INTEGER NOT NULL DEFAULT 1,
    UNIQUE (tenant_id, code, currency)
);

CREATE TABLE journal_entries (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    tenant_id UUID NOT NULL,
    idempotency_key TEXT NOT NULL,
    description TEXT NOT NULL,
    posted_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (tenant_id, idempotency_key)
);

CREATE TABLE ledger_postings (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    journal_entry_id UUID NOT NULL REFERENCES journal_entries(id) ON DELETE RESTRICT,
    account_id UUID NOT NULL REFERENCES ledger_accounts(id) ON DELETE RESTRICT,
    -- Positive = Credit, Negative = Debit (invariant: SUM(signed_amount_cents) per journal_entry_id == 0)
    signed_amount_cents BIGINT NOT NULL CHECK (signed_amount_cents <> 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
```

### Pattern C: Hierarchy & Tree Topologies in Relational Databases

| Pattern | Schema Shape | Subtree Read Cost | Move Subtree Write Cost | Best Business Fit |
|---|---|---|---|---|
| **Adjacency List** | `parent_id UUID REFERENCES nodes(id)` | Recursive CTE (`WITH RECURSIVE`) | $O(1)$ single row update | Org charts, threaded comments, frequent reorganizations |
| **Materialized Path** | `path TEXT NOT NULL` (`'/root/ops/eng/'` with B-Tree `text_pattern_ops` or `ltree`) | $O(\log N)$ index prefix scan (`path LIKE '/root/ops/%'`) | $O(K)$ subtree string prefix update | File/folder trees, e-commerce breadcrumbs |
| **Closure Table** | `node_paths(ancestor_id, descendant_id, depth)` | $O(\log N)$ single index join | $O(A \times D)$ path table re-insert | Deep hierarchical permissions, multi-level rollups / BOM |

---

## 2. Workload-to-Storage-Engine Decision Matrix

| Business Workload | Primary Access Pattern | Recommended Storage Engine | Why / Operational Guardrail |
|---|---|---|---|
| **Core Transactional Domain (OLTP)** | Point lookups, short range scans, multi-row ACID invariants | **PostgreSQL** or **MySQL (InnoDB)** | Industry-standard ACID guarantees, rich constraints, row locking, and mature operational tooling. |
| **Local-First / CLI / Desktop / Single-Node Edge** | Embedded low-latency reads/writes without network hop | **SQLite (`PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; STRICT` tables)** | Zero network latency, zero ops overhead, handles 10k+ reads/sec and sequential writes cleanly on local NVMe. |
| **High-Volume Telemetry, Event Logs, OLAP** | Append-only batch inserts, wide time-range aggregations (`SUM`, `AVG`, `PERCENTILE`) | **ClickHouse / DuckDB / TimescaleDB / Parquet** | Columnar compression (10-20x) and vectorized scans avoid B-tree write amplification and buffer-pool thrashing. |
| **Ephemeral Locks, Rate Limiting, Session Holds** | Sub-millisecond key-value lookups with automatic TTL expiry | **Redis / Valkey** (or unlogged PG table with TTL sweeper) | Never use ephemeral KV stores as the sole system of record for billing or durable orders. |
| **Full-Text & Semantic Vector Search** | Keyword BM25 ranking + $k$-NN embedding similarity | **PostgreSQL (`tsvector` + `pgvector` HNSW)** or **SQLite `FTS5`** up to ~5M docs; **Meilisearch / Qdrant / OpenSearch** beyond | Start in-database to avoid dual-store sync; when scaling out to a dedicated search engine, feed it via **Transactional Outbox**. |

---

## 3. The ESR (Equality, Sort, Range) Composite Indexing Matrix

For the query:
```sql
SELECT id, customer_id, total_cents, created_at
FROM orders
WHERE tenant_id = $1            -- Equality (E)
  AND status = $2               -- Equality (E)
  AND total_cents >= $3         -- Range (R)
ORDER BY created_at DESC, id DESC -- Sort (S)
LIMIT 25;
```

| Index Column Order | Execution Plan Outcome | Verdict |
|---|---|---|
| `(tenant_id, status, total_cents, created_at DESC)` | Range column `total_cents` precedes Sort column `created_at`. B-tree sort order is broken after the inequality; engine must execute an in-memory/disk `Sort`. | **Anti-Pattern** |
| `(tenant_id, status, created_at DESC, id DESC, total_cents) INCLUDE (customer_id)` | **E**quality narrows to exact slice, **S**ort reads rows in order and stops after 25 matches, **R**ange filters in-index, `INCLUDE` achieves **Index-Only Scan**. | **Optimal (ESR + Covering)** |

---

## 4. Multi-ORM & Multi-Stack Strict Schema Equivalents

### Drizzle ORM (`schema.ts` — PostgreSQL)
```typescript
import { pgTable, uuid, bigint, char, text, integer, timestamp, index, uniqueIndex } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';

export const orders = pgTable('orders', {
  id: uuid('id').primaryKey().default(sql`uuidv7()`),
  tenantId: uuid('tenant_id').notNull(),
  customerId: uuid('customer_id').notNull(),
  subtotalCents: bigint('subtotal_cents', { mode: 'bigint' }).notNull(),
  taxCents: bigint('tax_cents', { mode: 'bigint' }).notNull(),
  currency: char('currency', { length: 3 }).notNull().default('USD'),
  status: text('status').notNull().default('PENDING'),
  idempotencyKey: text('idempotency_key').notNull(),
  version: integer('version').notNull().default(1),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
}, (table) => ({
  tenantIdempotencyUq: uniqueIndex('uq_orders_tenant_idempotency').on(table.tenantId, table.idempotencyKey),
  tenantStatusEsrIdx: index('idx_orders_tenant_status_esr')
    .on(table.tenantId, table.status, table.createdAt.desc(), table.id.desc())
    .where(sql`${table.deletedAt} IS NULL`),
}));
```

### SQLAlchemy 2.0 (`models.py` — Python)
```python
from datetime import datetime
from uuid import UUID
from sqlalchemy import BigInteger, CheckConstraint, DateTime, ForeignKey, Index, Integer, String, UniqueConstraint, text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[UUID] = mapped_column(primary_key=True, server_default=text("uuidv7()"))
    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id", ondelete="RESTRICT"), nullable=False)
    customer_id: Mapped[UUID] = mapped_column(ForeignKey("customers.id", ondelete="RESTRICT"), nullable=False)
    subtotal_cents: Mapped[int] = mapped_column(BigInteger, nullable=False)
    tax_cents: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, server_default="USD")
    status: Mapped[str] = mapped_column(String(32), nullable=False, server_default="PENDING")
    idempotency_key: Mapped[str] = mapped_column(String(128), nullable=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False, server_default="1")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=text("clock_timestamp()"))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        CheckConstraint("subtotal_cents >= 0 AND tax_cents >= 0", name="chk_orders_non_negative_money"),
        UniqueConstraint("tenant_id", "idempotency_key", name="uq_orders_tenant_idempotency"),
        Index(
            "idx_orders_tenant_status_esr",
            "tenant_id",
            "status",
            text("created_at DESC"),
            text("id DESC"),
            postgresql_where=text("deleted_at IS NULL"),
        ),
    )
```

### Go / GORM & SQLx (`models.go`)
```go
package models

import (
	"time"
	"github.com/google/uuid"
)

type Order struct {
	ID             uuid.UUID  `db:"id" gorm:"type:uuid;primaryKey;default:uuidv7()"`
	TenantID       uuid.UUID  `db:"tenant_id" gorm:"type:uuid;not null;index:idx_orders_tenant_status_esr,priority:1"`
	CustomerID     uuid.UUID  `db:"customer_id" gorm:"type:uuid;not null;index"`
	SubtotalCents  int64      `db:"subtotal_cents" gorm:"type:bigint;not null"` // Always int64 minor units, never float64
	TaxCents       int64      `db:"tax_cents" gorm:"type:bigint;not null"`
	Currency       string     `db:"currency" gorm:"type:char(3);not null;default:'USD'"`
	Status         string     `db:"status" gorm:"type:text;not null;index:idx_orders_tenant_status_esr,priority:2"`
	IdempotencyKey string     `db:"idempotency_key" gorm:"type:text;not null"`
	Version        int32      `db:"version" gorm:"not null;default:1"`
	CreatedAt      time.Time  `db:"created_at" gorm:"type:timestamptz;not null;index:idx_orders_tenant_status_esr,priority:3,sort:desc"`
	DeletedAt      *time.Time `db:"deleted_at" gorm:"type:timestamptz"`
}
```

---
name: database-architecture
description: First-principles, business-domain-driven database architecture, data modeling, and query engineering (engine & ORM agnostic) - domain truth (state vs immutable ledger vs point-in-time snapshots), aggregate boundaries, workload-driven storage engine selection, ORM read/write separation (zero N+1), UUIDv7/BIGINT identity, strict types (TIMESTAMPTZ, minor-unit money), ESR composite indexing, keyset pagination, concurrency/leases & Transactional Outbox, multi-tenant RLS, and zero-downtime evolution.
when_to_use: Designing a data model from business requirements, choosing a storage engine, writing or reviewing SQL/ORM schemas (PostgreSQL, MySQL, SQLite, Prisma, Drizzle, SQLAlchemy, GORM, TypeORM), migrations, indexes, or queries. Do NOT use for pure in-memory UI state or static file assets.
paths:
  - "**/*.sql"
  - "**/*.prisma"
  - "**/migrations/**"
  - "**/schema.*"
  - "**/models/**"
  - "**/entities/**"
  - "**/db/**"
---

# Database Architecture & First-Principles Data Engineering

Database engineering is not picking a favourite ORM or copying boilerplate CRUD tables. It is **translating business domain truths, invariants, and access workloads into a data model and storage engine that cannot silently corrupt state or collapse under load**.

Every schema, ORM model, query, and migration must obey the **8 Core Database Engineering Pillars**.

## 1. Domain-to-Data Translation & Nature of Business Truth

Before defining tables or collections, classify every piece of business data by its **temporal nature of truth**:

| Business Data Nature | Modeling Rule | Classic Defect if Violated |
|---|---|---|
| **Mutable Current State** (Profile settings, draft cart, feature flags) | Normalized row updated in-place (`UPDATE ... SET version = version + 1`). | Using append-only logs for simple mutable settings without compaction. |
| **Point-in-Time Historical Snapshot** (Order line item price, invoice tax rate, shipping address at checkout, signed contract terms) | **Freeze snapshot attributes directly on the transaction record** (`unit_price_cents_at_purchase`, `tax_rate_bps_snapshot`, `billing_address_snapshot`) alongside an optional FK to the catalog entity. | Relying on a live `JOIN` to `products.price` or `users.address` — when a merchant edits a product price tomorrow, every historical invoice changes. |
| **Immutable Append-Only Ledger / Fact** (Payments, wallet balances, inventory movements, compliance audit trail) | **Source of Truth is an append-only journal/ledger** (`INSERT` only; corrections are reversing entries, never `UPDATE`/`DELETE`). Current balance is a derived projection or atomically maintained column backed by ledger sum invariants (`SUM(debit) = SUM(credit)`). | Updating `wallets.balance` in-place with no ledger trail — impossible to audit or reconcile after a partial failure. |
| **Bi-Temporal Business Facts** (Subscription tiers, employee compensation, insurance coverage, price books) | Separate **Effective Time** (`effective_from`, `effective_to` in business reality) from **System Time** (`recorded_at` when known to the DB), enforced with non-overlapping range constraints. | Overwriting a price or salary with `UPDATE`, destroying retroactive billing or payroll calculation accuracy. |

## 2. Aggregate Boundaries, Domain Topology & Normalization Balance

- **Aggregate Root & Transaction Boundary Alignment**: Group entities that must satisfy an immediate synchronous business invariant into a single **Aggregate** (mutated in one ACID transaction). Cross-aggregate references store **IDs only** and coordinate asynchronously via **Transactional Outbox** — never couple unrelated domains in a multi-service or 12-table distributed lock.
- **3NF Write Model + Deliberate Read Projections (CQRS-Lite)**:
  - Model the write path in **3NF** so every business fact has a single canonical owner.
  - Introduce denormalized columns, counter caches, or read-optimized projections *only* when a measured read SLA demands it, and declare in `docs/architecture.md`: **(1) Canonical SSOT**, **(2) Sync Mechanism** (same-tx trigger, outbox consumer, or concurrent materialized view), and **(3) Staleness & Reconciliation Bound**.
- **Structural Patterns for Complex Business Topologies**:
  - *Hierarchies (Org charts, Categories, Folders, BOM)*: Choose **Adjacency List** (`parent_id` + recursive CTE) for frequent tree moves, **Materialized Path** (`path = '/1/4/9/'`) for fast prefix subtree reads, or **Closure Table** (`ancestor_id, descendant_id, depth`) for deep permission/analytic queries.
  - *Polymorphism*: Use **Class-Table Inheritance** (shared base table + subtype tables with FK) or **Single-Table with discriminated `CHECK` constraints** — never a sparse table with 40 unvalidated nullable columns or polymorphic FKs without referential integrity.
  - *State Lifecycles*: Model explicit state machines (`status` + transition history table recording `from_state`, `to_state`, `actor_id`, `reason`, `created_at`), never uncoordinated boolean flags (`is_paid && is_cancelled`).

## 3. Workload-Driven Storage Engine Selection (Fit-for-Purpose Pragmatism)

Select the storage engine from the **business workload shape** (Read/Write ratio, data structure, latency SLA, operational footprint) — never add a second database when your primary engine handles the scale cleanly:

| Workload Shape | Fit-for-Purpose Engine | Architectural Rule |
|---|---|---|
| **Transactional Business Domain (OLTP)** | **PostgreSQL / MySQL** (or **SQLite in `WAL` + `STRICT` mode** for local-first, CLI, desktop, or single-node edge apps) | Default system of record. Squeeze full capability (JSONB, FTS, row locks, range types) before adding infrastructure. |
| **High-Ingest Telemetry, Logs & OLAP Analytics** | **ClickHouse / DuckDB / Timescale / Parquet** | Do not hammer OLTP B-trees with millions of append-only time-series metrics or full-table analytical scans. |
| **Sub-ms Ephemeral State, Rate Limits & Hot Holds** | **Redis / In-Memory + DB Reservation Lease** | Cache and ephemeral state are disposable; durable financial/booking truth still commits to the primary transactional store. |
| **Full-Text Search & Vector Retrieval** | **Built-in (`tsvector` / SQLite `FTS5` / `pgvector` HNSW)** first; dedicated engine (**Meilisearch / OpenSearch / Qdrant**) only at scale | When splitting to an external search/vector index, sync strictly via **Transactional Outbox / CDC**, never dual-write in HTTP handlers. |

Detailed domain schemas and engine matrix: `references/relational-and-indexing.md`.

## 4. ORM & Data-Access Layer Engineering (Stack-Agnostic)

Whether using **Raw SQL / SQLx, Prisma, Drizzle, SQLAlchemy, Django ORM, GORM, TypeORM, Entity Framework, or Hibernate**:
- **Domain Model ≠ Persistence Row**: Keep business invariant methods pure; never leak ORM lazy-loading proxies into HTTP serializers or UI templates.
- **Zero Query-in-Loop (`N+1` Waterfall Ban)**: Never execute a query inside a `for`/`while`/`.map()` loop (`query_in_loop_hazard`). Always batch-fetch via `WHERE id IN (...)`, `JOIN`, `selectinload` / `preload` / `include`, or DataLoader.
- **Write Path vs. Read Path Separation**: Mutate via aggregate repositories or atomic conditional statements; execute read/list endpoints as flat projections (`SELECT` explicit columns into DTOs — never `SELECT *` or hydrating deep 5-level ORM object graphs just to render a summary table).

## 5. Identity, Strict Data Types & Mechanical Constraints

- **Dual-Identity Strategy**:
  - **Internal Primary Key**: Time-ordered `UUIDv7` or `BIGINT` identity for sequential B-tree leaf inserts (zero random page splits). Random `UUIDv4` is **forbidden** as a clustered/B-tree primary key on high-write tables.
  - **Public / URL Identifier**: Opaque `UUIDv7` or prefixed ULID/NanoID (`ord_01H8...`, `inv_01H8...`) to prevent IDOR enumeration (`GET /orders/1001`, `1002`).
- **Universal Type Integrity Across All DBs & ORMs**:
  - **Timestamps**: Always UTC timezone-aware (`TIMESTAMPTZ` / ISO-8601 UTC epoch). Naive `TIMESTAMP` / `DATETIME` is **blocking**.
  - **Money & Quantities**: Always integer minor units (`BIGINT` cents/satoshis + `currency CHAR(3)`) or exact decimal (`NUMERIC(19, 4)` / `Decimal`). IEEE-754 floats (`FLOAT`, `REAL`, `DOUBLE`, `Float`, `doublePrecision`, `float64`) are **strictly forbidden** for money in every DB and ORM.
  - **Schemaless / JSON Columns**: Allowed only for boundary-validated extension metadata; forbidden for core relationships or join keys.
- **Database-Enforced Invariants**: Application validation is bypassed by race conditions and scripts. Enforce `FOREIGN KEY ... ON DELETE RESTRICT | CASCADE`, `CHECK (...)`, partial `UNIQUE`, and booking overlap exclusion at the storage layer.

## 6. Access-Pattern-Driven Indexing (ESR Rule) & Keyset Pagination

- **The ESR Rule for Composite B-Tree Indexes**: Order columns strictly as **E**quality (`=`, `IN`) → **S**ort (`ORDER BY`) → **R**ange (`>`, `<`, `BETWEEN`). Placing a range column before a sort column breaks B-tree ordering and forces an in-memory/disk sort.
- **Index Every Foreign Key**, use **Covering Indexes (`INCLUDE`)** for Index-Only Scans on hot endpoints, and **Partial Indexes (`WHERE`)** for active/pending subsets.
- **Keyset (Seek) Pagination Only**: Ban deep `OFFSET` pagination ($O(N)$ scan discard). Paginate with a deterministic cursor (`WHERE (created_at, id) < ($1, $2) ORDER BY created_at DESC, id DESC LIMIT 25`).

## 7. Concurrency, Reservation Leases & Transactional Outbox

- **Zero Network I/O Inside DB Transactions**: Never call payment gateways, LLMs, webhooks, or message brokers inside `BEGIN ... COMMIT`.
- **Match Concurrency Control to Business Contention**:
  - *Low-conflict document/profile edits*: **Optimistic Locking** (`WHERE id = $1 AND version = $2`).
  - *Wallets, quotas, stock counters*: **Atomic Conditional Update** (`SET balance = balance - $1 WHERE id = $2 AND balance >= $1`).
  - *Flash sales, seat/inventory holds*: **Time-Bounded Reservation Lease** (`reservations` row with `status = 'HELD'`, `expires_at = now() + interval '10 min'`, and idempotency key) converted to confirmed order upon payment webhook.
  - *Worker queues*: **Skip-Locked Claim** (`FOR UPDATE SKIP LOCKED`).
- **Transactional Outbox Pattern**: Persist domain mutations and `outbox_events` in the **same ACID transaction**; publish asynchronously via an idempotent relay worker.

Detailed ORM patterns, reservation leases, and outbox playbooks: `references/scalability-and-consistency.md`.

## 8. Multi-Tenancy, Data Lifecycle, Privacy & Zero-Downtime Evolution

- **Multi-Tenant Isolation**: Every tenant table carries `tenant_id`, leads composite indexes with `tenant_id`, and enforces Row-Level Security (`ENABLE + FORCE ROW LEVEL SECURITY`) or mandatory tenant-scoped query predicates verified by cross-tenant negative tests.
- **Soft-Delete vs. Audit History**: When `deleted_at` is used, replace plain `UNIQUE` constraints with **Partial Unique Indexes (`WHERE deleted_at IS NULL`)**. When the business requirement is auditability rather than "trash restore", use hard deletes on the operational table plus an immutable `_history` / `audit_logs` table.
- **Partitioning, PII & Expand-and-Contract**: Isolate PII for GDPR erasure (crypto-shredding or separate PII table), partition tables exceeding 50M rows by time range, and evolve schemas via **Expand → Backfill/Dual-Write → Contract** (`CREATE INDEX CONCURRENTLY`, `NOT VALID` constraints).
- **Mechanical Verification**: Run the multi-stack Database Architecture Gate before completing any schema, ORM model, migration, or query task:
  ```bash
  python3 "${CLAUDE_PLUGIN_ROOT}/scripts/db_architecture_gate.py" . --strict
  ```

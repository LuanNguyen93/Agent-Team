import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import db_architecture_gate  # noqa: E402


class TestDbArchitectureGate(unittest.TestCase):
    def test_detects_float_money_and_naive_timestamp_in_sql_and_prisma(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            (ws / "schema.sql").write_text(
                "CREATE TABLE invoices (\n"
                "    id UUID PRIMARY KEY,\n"
                "    total_amount FLOAT NOT NULL,\n"
                "    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL\n"
                ");\n",
                encoding="utf-8",
            )
            (ws / "schema.prisma").write_text(
                "model Product {\n"
                "  id    String @id\n"
                "  price Float\n"
                "}\n",
                encoding="utf-8",
            )
            rep = db_architecture_gate.scan_workspace_db(ws)
            kinds = [f["kind"] for f in rep["findings"]]
            self.assertIn("float_money_column", kinds)
            self.assertIn("naive_timestamp", kinds)
            float_count = sum(1 for k in kinds if k == "float_money_column")
            self.assertGreaterEqual(float_count, 2)

    def test_detects_offset_pagination_and_select_star(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            (ws / "repository.py").write_text(
                'def list_orders(db):\n'
                '    return db.execute("SELECT * FROM orders ORDER BY created_at DESC LIMIT 20 OFFSET 100")\n',
                encoding="utf-8",
            )
            rep = db_architecture_gate.scan_workspace_db(ws)
            kinds = [f["kind"] for f in rep["findings"]]
            self.assertIn("unbounded_select_star", kinds)
            self.assertIn("offset_pagination_hazard", kinds)

    def test_detects_soft_delete_plain_unique_hazard(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            (ws / "users.sql").write_text(
                "CREATE TABLE users (\n"
                "    id UUID PRIMARY KEY,\n"
                "    email TEXT UNIQUE,\n"
                "    deleted_at TIMESTAMPTZ\n"
                ");\n",
                encoding="utf-8",
            )
            rep = db_architecture_gate.scan_workspace_db(ws)
            kinds = [f["kind"] for f in rep["findings"]]
            self.assertIn("soft_delete_unique_hazard", kinds)

    def test_detects_non_concurrent_index_in_strict_migration_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            mig_dir = ws / "migrations"
            mig_dir.mkdir()
            (mig_dir / "002_add_idx.sql").write_text(
                "CREATE INDEX idx_orders_user ON orders (user_id);\n"
                "ALTER TABLE orders DROP COLUMN legacy_code;\n",
                encoding="utf-8",
            )
            rep = db_architecture_gate.scan_workspace_db(ws, strict_migrations=True)
            kinds = [f["kind"] for f in rep["findings"]]
            self.assertIn("non_concurrent_index_or_lock_hazard", kinds)

    def test_clean_industrial_schema_and_keyset_query_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            mig_dir = ws / "migrations"
            mig_dir.mkdir()
            (mig_dir / "001_init.sql").write_text(
                "CREATE TABLE users (\n"
                "    id UUID PRIMARY KEY,\n"
                "    tenant_id UUID NOT NULL,\n"
                "    email TEXT NOT NULL,\n"
                "    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),\n"
                "    deleted_at TIMESTAMPTZ\n"
                ");\n"
                "CREATE UNIQUE INDEX CONCURRENTLY idx_users_email_active\n"
                "    ON users (tenant_id, email) WHERE deleted_at IS NULL;\n"
                "CREATE TABLE orders (\n"
                "    id UUID PRIMARY KEY,\n"
                "    tenant_id UUID NOT NULL,\n"
                "    amount_cents BIGINT NOT NULL CHECK (amount_cents >= 0),\n"
                "    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()\n"
                ");\n"
                "CREATE INDEX CONCURRENTLY idx_orders_tenant_created\n"
                "    ON orders (tenant_id, created_at DESC, id DESC);\n",
                encoding="utf-8",
            )
            (ws / "queries.sql").write_text(
                "SELECT id, amount_cents, created_at\n"
                "FROM orders\n"
                "WHERE tenant_id = $1 AND (created_at, id) < ($2, $3)\n"
                "ORDER BY created_at DESC, id DESC\n"
                "LIMIT 25;\n",
                encoding="utf-8",
            )
            rep = db_architecture_gate.scan_workspace_db(ws, strict_migrations=True)
            self.assertEqual(rep["finding_count"], 0, rep["findings"])

    def test_detects_multi_orm_float_money_across_sqlalchemy_drizzle_typeorm_gorm(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            (ws / "models.py").write_text(
                "from sqlalchemy import Column, Float\n"
                "class Invoice:\n"
                "    total_amount = Column(Float, nullable=False)\n",
                encoding="utf-8",
            )
            (ws / "schema.ts").write_text(
                "import { pgTable, doublePrecision } from 'drizzle-orm/pg-core';\n"
                "export const products = pgTable('products', {\n"
                "  unit_price: doublePrecision('unit_price').notNull(),\n"
                "});\n",
                encoding="utf-8",
            )
            (ws / "order.entity.ts").write_text(
                "export class OrderEntity {\n"
                "  @Column({ type: 'float' })\n"
                "  total_fee: number;\n"
                "}\n",
                encoding="utf-8",
            )
            (ws / "models.go").write_text(
                "package models\n"
                "type Wallet struct {\n"
                "    Balance float64 `gorm:\"column:balance\"`\n"
                "}\n",
                encoding="utf-8",
            )
            rep = db_architecture_gate.scan_workspace_db(ws)
            float_findings = [f for f in rep["findings"] if f["kind"] == "float_money_column"]
            self.assertEqual(len(float_findings), 4, rep["findings"])

    def test_detects_orm_query_in_loop_n_plus_one_hazard(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            (ws / "service.ts").write_text(
                "export async function loadOrders(prisma: any, ids: string[]) {\n"
                "  const out = [];\n"
                "  for (const id of ids) {\n"
                "    const order = await prisma.order.findUnique({ where: { id } });\n"
                "    out.push(order);\n"
                "  }\n"
                "  return out;\n"
                "}\n",
                encoding="utf-8",
            )
            (ws / "repo.py").write_text(
                "def fetch_items(session, item_ids):\n"
                "    for item_id in item_ids:\n"
                "        session.execute('SELECT id FROM items WHERE id = :id', {'id': item_id})\n",
                encoding="utf-8",
            )
            (ws / "multiline.ts").write_text(
                "export async function loadMultiline(prisma: any, ids: string[]) {\n"
                "  for (\n"
                "    const id of ids\n"
                "  ) {\n"
                "    await prisma.order.findUnique({ where: { id } });\n"
                "  }\n"
                "}\n",
                encoding="utf-8",
            )
            rep = db_architecture_gate.scan_workspace_db(ws)
            n1_findings = [f for f in rep["findings"] if f["kind"] == "query_in_loop_hazard"]
            self.assertEqual(len(n1_findings), 3, rep["findings"])


if __name__ == "__main__":
    unittest.main()

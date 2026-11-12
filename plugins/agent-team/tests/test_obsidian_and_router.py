import os
import subprocess
import sys
import tempfile
import unittest

from _load import ROOT, load


class TestObsidianDistill(unittest.TestCase):
    def setUp(self):
        self.mod = load(os.path.join("skills", "obsidian-second-brain", "scripts"), "obsidian_distill")
        self.tmp = tempfile.TemporaryDirectory()
        self.vault = os.path.join(self.tmp.name, "vault")

    def tearDown(self):
        self.tmp.cleanup()

    def test_distill_creates_note_and_updates_moc(self):
        note_path = self.mod.distill_note(
            vault_dir=self.vault,
            note_type="rca",
            title="Stripe Webhook Idempotency Race",
            domain="fintech",
            summary="Concurrent retries caused duplicate ledger entries without unique constraint.",
            details="Use `INSERT ... ON CONFLICT (idempotency_key) DO NOTHING` before posting ledger lines.",
            confidence="observed",
            verified_by="pytest tests/test_webhooks.py",
            links=["[[domain-fintech-ledger]]"],
            tags=["fintech", "stripe", "idempotency"],
        )
        self.assertTrue(os.path.isfile(note_path))
        with open(note_path, encoding="utf-8") as fh:
            content = fh.read()
        self.assertIn("id: rca-stripe-webhook-idempotency-race", content)
        self.assertIn("type: rca", content)
        self.assertIn("domain: fintech", content)
        self.assertIn("confidence: observed", content)
        self.assertIn("verified_by: \"pytest tests/test_webhooks.py\"", content)
        self.assertIn("> [!abstract] Essence", content)
        self.assertIn("[[domain-fintech-ledger]]", content)

        moc_path = os.path.join(self.vault, "00-MOC.md")
        self.assertTrue(os.path.isfile(moc_path))
        with open(moc_path, encoding="utf-8") as fh:
            moc = fh.read()
        self.assertIn("[[rca-stripe-webhook-idempotency-race|Stripe Webhook Idempotency Race]]", moc)

    def test_distill_merges_existing_note_without_duplicating_moc(self):
        self.mod.distill_note(
            vault_dir=self.vault,
            note_type="adr",
            title="Single Postgres Queue Over Kafka",
            domain="architecture",
            summary="Use FOR UPDATE SKIP LOCKED at < 1k jobs/sec.",
            details="Initial decision for v1.",
            confidence="observed",
            verified_by="cargo test",
        )
        note_path = self.mod.distill_note(
            vault_dir=self.vault,
            note_type="adr",
            title="Single Postgres Queue Over Kafka",
            domain="architecture",
            summary="Use FOR UPDATE SKIP LOCKED at < 1k jobs/sec.",
            details="Benchmark confirmed p99 < 12ms at 500 jobs/sec.",
            confidence="observed",
            verified_by="cargo bench",
        )
        with open(note_path, encoding="utf-8") as fh:
            content = fh.read()
        self.assertIn("Initial decision for v1.", content)
        self.assertIn("Benchmark confirmed p99 < 12ms at 500 jobs/sec.", content)

        moc_path = os.path.join(self.vault, "00-MOC.md")
        with open(moc_path, encoding="utf-8") as fh:
            moc = fh.read()
        self.assertEqual(moc.count("[[adr-single-postgres-queue-over-kafka|"), 1)

    def test_lint_vault_detects_missing_frontmatter_and_broken_links(self):
        self.mod.distill_note(
            vault_dir=self.vault,
            note_type="domain",
            title="B2B Tenant Isolation",
            domain="saas",
            summary="Every tenant query must filter by tenant_id via RLS.",
            details="Verified with second-tenant isolation test.",
            confidence="observed",
            verified_by="npm test",
        )
        report_clean = self.mod.lint_vault(self.vault)
        self.assertEqual(report_clean["errors"], [])

        # Add a note with broken wikilink and missing frontmatter
        bad_note = os.path.join(self.vault, "broken.md")
        with open(bad_note, "w", encoding="utf-8") as fh:
            fh.write("# No Frontmatter\nLinks to [[non-existent-note]]\n")
        report_bad = self.mod.lint_vault(self.vault)
        self.assertGreaterEqual(len(report_bad["errors"]), 2)

        # Add an orphan note with valid frontmatter but no link in 00-MOC.md or to [[00-MOC]]
        orphan_note = os.path.join(self.vault, "pattern-orphan.md")
        with open(orphan_note, "w", encoding="utf-8") as fh:
            fh.write(
                "---\nid: pattern-orphan\ntitle: \"Orphan\"\ntype: pattern\n"
                "domain: test\nconfidence: observed\nverified_by: \"manual\"\n---\n"
                "# Orphan Note\nNo links here.\n"
            )
        report_orphan = self.mod.lint_vault(self.vault)
        self.assertTrue(any("orphan" in e.lower() for e in report_orphan["errors"]))

    def test_cli_lint_positional_dir_and_merge_flag(self):
        script_path = os.path.join(ROOT, "skills", "obsidian-second-brain", "scripts", "obsidian_distill.py")
        proc_create = subprocess.run(
            [
                sys.executable, script_path,
                "--vault", self.vault,
                "--type", "pattern",
                "--title", "Parse Dont Validate",
                "--domain", "engineering",
                "--summary", "Parse at the edge.",
                "--merge",
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc_create.returncode, 0, proc_create.stderr)

        proc_lint = subprocess.run(
            [sys.executable, script_path, "--lint", self.vault],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc_lint.returncode, 0, proc_lint.stderr)


class TestFastRouterOffline(unittest.TestCase):
    def setUp(self):
        self.router = load("scripts", "fast_router")

    def test_offline_classification_tiers(self):
        d_quick = self.router.classify_offline("Fix typo in login button label")
        self.assertEqual(d_quick.tier, "QUICK")
        self.assertGreaterEqual(d_quick.confidence, 0.8)

        d_feature = self.router.classify_offline(
            "Add user avatar upload API with S3 storage and an upload dialog in profile settings"
        )
        self.assertEqual(d_feature.tier, "FEATURE")
        self.assertTrue(d_feature.parallel_safe)

        # Ensure 'comment' or 'color' inside a feature request is not misclassified as QUICK
        d_comment_feat = self.router.classify_offline(
            "Add user comment API endpoint and UI table"
        )
        self.assertEqual(d_comment_feat.tier, "FEATURE")

        d_project = self.router.classify_offline(
            "Design and build a multi-tenant B2B billing platform from scratch"
        )
        self.assertEqual(d_project.tier, "PROJECT")

    def test_strike_loop_detector(self):
        # Two identical error signatures trigger a circuit-breaker pivot decision
        res = self.router.check_strike_loop([
            "AssertionError: expected 400 got 200 in test_auth.py",
            "AssertionError: expected 400 got 200 in test_auth.py",
        ])
        self.assertTrue(res["circuit_break"])
        self.assertEqual(res["strikes"], 2)
        self.assertEqual(res["action"], "STOP_REVERT_AND_PIVOT")

    def test_cli_offline_flag_runs_without_api_key(self):
        script_path = os.path.join(ROOT, "scripts", "fast_router.py")
        env = dict(os.environ)
        env.pop("GEMINI_API_KEY", None)
        env.pop("GOOGLE_API_KEY", None)
        proc = subprocess.run(
            [sys.executable, script_path, "--offline", "--format", "line", "Fix null check in user utils"],
            env=env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("`QUICK`", proc.stdout)


if __name__ == "__main__":
    unittest.main()

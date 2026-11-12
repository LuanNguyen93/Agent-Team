import os
import subprocess
import sys
import tempfile
import unittest

from _load import ROOT, load


class TestTaskSync(unittest.TestCase):
    def setUp(self):
        self.mod = load("scripts", "task_sync")
        self.tmp = tempfile.TemporaryDirectory()
        self.ws = self.tmp.name
        self.docs = os.path.join(self.ws, "docs")
        os.makedirs(self.docs, exist_ok=True)

    def tearDown(self):
        self.tmp.cleanup()

    def test_audit_detects_unchecked_markdown_boxes(self):
        plan_path = os.path.join(self.docs, "plan.md")
        with open(plan_path, "w", encoding="utf-8") as fh:
            fh.write(
                "# Plan\n"
                "- [x] Step 1: Create schema\n"
                "- [ ] Step 2: Implement handler\n"
                "- [ ] Step 3: Add tests\n"
            )
        report = self.mod.audit_workspace(self.ws)
        self.assertEqual(report["total_checkboxes"], 3)
        self.assertEqual(report["checked_checkboxes"], 1)
        self.assertEqual(report["unchecked_checkboxes"], 2)
        self.assertEqual(len(report["unchecked_items"]), 2)

    def test_tick_markdown_checkbox_with_evidence(self):
        plan_path = os.path.join(self.docs, "plan.md")
        with open(plan_path, "w", encoding="utf-8") as fh:
            fh.write(
                "# Plan\n"
                "- [ ] Step 1: Create schema\n"
                "- [ ] Step 2: Implement handler\n"
            )
        updated = self.mod.tick_item(
            file_path=plan_path,
            match_text="Step 1: Create schema",
            evidence="pytest tests/test_schema.py",
        )
        self.assertTrue(updated)
        with open(plan_path, encoding="utf-8") as fh:
            content = fh.read()
        self.assertIn("- [x] Step 1: Create schema (`[observed: pytest tests/test_schema.py]`)", content)
        self.assertIn("- [ ] Step 2: Implement handler", content)

    def test_tick_features_csv_row(self):
        csv_path = os.path.join(self.docs, "features.csv")
        with open(csv_path, "w", encoding="utf-8") as fh:
            fh.write(
                "feature,area,priority,original,clone,notes\n"
                "User login,auth,must,yes,no,\n"
                "Export CSV,reports,should,yes,no,\n"
            )
        updated = self.mod.tick_csv_feature(
            csv_path=csv_path,
            feature_match="User login",
            status="yes",
            evidence="npm test auth",
        )
        self.assertTrue(updated)
        report = self.mod.audit_workspace(self.ws)
        self.assertEqual(report["csv_must_Remaining"], 0)

    def test_cli_require_all_checked_exits_nonzero_when_stale(self):
        plan_path = os.path.join(self.docs, "plan.md")
        with open(plan_path, "w", encoding="utf-8") as fh:
            fh.write("# Plan\n- [ ] Unfinished step\n")
        script_path = os.path.join(ROOT, "scripts", "task_sync.py")
        proc_fail = subprocess.run(
            [sys.executable, script_path, self.ws, "--require-all-checked"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc_fail.returncode, 1)

        proc_tick = subprocess.run(
            [
                sys.executable, script_path, self.ws,
                "--tick", "Unfinished step",
                "--file", plan_path,
                "--evidence", "unit test pass",
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc_tick.returncode, 0, proc_tick.stderr)

        proc_pass = subprocess.run(
            [sys.executable, script_path, self.ws, "--require-all-checked"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc_pass.returncode, 0, proc_pass.stderr)


if __name__ == "__main__":
    unittest.main()

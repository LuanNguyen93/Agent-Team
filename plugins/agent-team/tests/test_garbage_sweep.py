import os
import subprocess
import sys
import tempfile
import unittest

from _load import ROOT, load


class TestGarbageSweep(unittest.TestCase):
    def setUp(self):
        self.mod = load("scripts", "garbage_sweep")
        self.tmp = tempfile.TemporaryDirectory()
        self.ws = self.tmp.name
        self.docs = os.path.join(self.ws, "docs")
        self.src = os.path.join(self.ws, "src")
        os.makedirs(self.docs, exist_ok=True)
        os.makedirs(self.src, exist_ok=True)

    def tearDown(self):
        self.tmp.cleanup()

    def test_detects_competing_doc_variants_and_auto_archives(self):
        # Create canonical brief.md + two stale competing variants
        with open(os.path.join(self.docs, "brief.md"), "w", encoding="utf-8") as fh:
            fh.write("# Canonical Brief\n")
        with open(os.path.join(self.docs, "brief-old-phase1.md"), "w", encoding="utf-8") as fh:
            fh.write("# Old Phase 1 Brief\n")
        with open(os.path.join(self.docs, "prd.md"), "w", encoding="utf-8") as fh:
            fh.write("# Canonical PRD\n")
        with open(os.path.join(self.docs, "prd-draft-v1.md"), "w", encoding="utf-8") as fh:
            fh.write("# Draft V1 PRD\n")

        report = self.mod.scan_docs(self.ws)
        self.assertEqual(len(report["competing_variants"]), 2)

        # Auto-archive moves competing variants into docs/archive/ with Status: Superseded
        moved = self.mod.archive_competing_docs(self.ws)
        self.assertEqual(len(moved), 2)
        self.assertFalse(os.path.exists(os.path.join(self.docs, "brief-old-phase1.md")))
        archived_file = os.path.join(self.docs, "archive", "brief-old-phase1.md")
        self.assertTrue(os.path.isfile(archived_file))
        with open(archived_file, encoding="utf-8") as fh:
            text = fh.read()
        self.assertIn("Status: Superseded", text)

        report_after = self.mod.scan_docs(self.ws)
        self.assertEqual(len(report_after["competing_variants"]), 0)

    def test_detects_code_garbage_symbols_and_commented_out_blocks(self):
        py_file = os.path.join(self.src, "service.py")
        with open(py_file, "w", encoding="utf-8") as fh:
            fh.write(
                "import os\n"
                "import json\n"
                "\n"
                "def process_order_old(order):\n"
                "    return False\n"
                "\n"
                "def process_order(order):\n"
                "    # def legacy_calc(x):\n"
                "    #     if x > 0:\n"
                "    #         return x * 2\n"
                "    #     return 0\n"
                "    return json.dumps(order)\n"
            )
        code_report = self.mod.scan_code(self.ws)
        reasons = [f["kind"] for f in code_report["findings"]]
        self.assertIn("unused_import", reasons)
        self.assertIn("backup_symbol_suffix", reasons)
        self.assertIn("commented_out_code", reasons)

    def test_cli_exits_nonzero_on_strict_violations(self):
        with open(os.path.join(self.docs, "brief.md"), "w", encoding="utf-8") as fh:
            fh.write("# Brief\n")
        with open(os.path.join(self.docs, "brief-v2.md"), "w", encoding="utf-8") as fh:
            fh.write("# Brief v2\n")

        script_path = os.path.join(ROOT, "scripts", "garbage_sweep.py")
        proc_fail = subprocess.run(
            [sys.executable, script_path, self.ws, "--strict"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc_fail.returncode, 1)

        proc_fix = subprocess.run(
            [sys.executable, script_path, self.ws, "--archive-stale-docs", "--strict"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc_fix.returncode, 0, proc_fix.stderr)


if __name__ == "__main__":
    unittest.main()

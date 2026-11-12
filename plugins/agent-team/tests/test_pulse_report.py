import os
import subprocess
import sys
import tempfile
import unittest

from _load import ROOT, load


class TestPulseReport(unittest.TestCase):
    def setUp(self):
        self.mod = load(os.path.join("skills", "pulse-report", "scripts"), "pulse_report")
        self.tmp = tempfile.TemporaryDirectory()
        self.job_a = os.path.join(self.tmp.name, "job-alpha")
        self.job_b = os.path.join(self.tmp.name, "job-beta")
        os.makedirs(os.path.join(self.job_a, "docs", "brain"), exist_ok=True)
        os.makedirs(os.path.join(self.job_b, "docs"), exist_ok=True)

        # Initialize git repo in job_a with one commit
        subprocess.run(["git", "init"], cwd=self.job_a, capture_output=True)
        subprocess.run(["git", "config", "user.email", "dev@example.com"], cwd=self.job_a, capture_output=True)
        subprocess.run(["git", "config", "user.name", "Dev"], cwd=self.job_a, capture_output=True)

        with open(os.path.join(self.job_a, "docs", "tasks.md"), "w", encoding="utf-8") as fh:
            fh.write(
                "# Tasks\n"
                "- [x] Implement Stripe webhook handler (`[observed: pytest]`)\n"
                "- [ ] Add retry backoff policy\n"
            )
        with open(os.path.join(self.job_a, "docs", "brain", "rca-webhook-race.md"), "w", encoding="utf-8") as fh:
            fh.write(
                "---\nid: rca-webhook-race\ntitle: \"Webhook Idempotency Race\"\n"
                "type: rca\ndomain: fintech\nconfidence: observed\nverified_by: \"pytest\"\n---\n"
                "# Webhook Idempotency Race\n"
            )
        subprocess.run(["git", "add", "."], cwd=self.job_a, capture_output=True)
        subprocess.run(["git", "commit", "-m", "feat: add Stripe webhook handler"], cwd=self.job_a, capture_output=True)

        # Job B: has features.csv and a task checklist
        with open(os.path.join(self.job_b, "docs", "tasks.md"), "w", encoding="utf-8") as fh:
            fh.write(
                "# Tasks\n"
                "- [x] Build S01 dashboard layout (`[observed: npm test]`)\n"
                "- [x] Wire OAuth redirect URI (`[observed: npm test]`)\n"
            )
        with open(os.path.join(self.job_b, "docs", "features.csv"), "w", encoding="utf-8") as fh:
            fh.write(
                "feature,area,priority,original,clone,notes\n"
                "Dashboard S01,ui,must,yes,yes,[observed: npm test]\n"
                "CSV Export,reports,must,yes,no,\n"
            )

    def tearDown(self):
        self.tmp.cleanup()

    def test_gather_multi_job_data(self):
        data = self.mod.gather_multi_job(
            workspaces=[self.job_a, self.job_b],
            period="daily",
        )
        self.assertEqual(len(data["jobs"]), 2)
        job_a_info = next(j for j in data["jobs"] if j["name"] == "job-alpha")
        self.assertGreaterEqual(len(job_a_info["commits"]), 1)
        self.assertIn("feat: add Stripe webhook handler", job_a_info["commits"][0]["subject"])
        self.assertEqual(len(job_a_info["checked_tasks"]), 1)
        self.assertEqual(len(job_a_info["unchecked_tasks"]), 1)
        self.assertEqual(len(job_a_info["brain_notes"]), 1)

        job_b_info = next(j for j in data["jobs"] if j["name"] == "job-beta")
        self.assertEqual(len(job_b_info["checked_tasks"]), 2)
        self.assertEqual(len(job_b_info["csv_done"]), 1)
        self.assertEqual(len(job_b_info["csv_pending_must"]), 1)

    def test_render_markdown_contains_isolated_job_standups_and_rollups(self):
        data = self.mod.gather_multi_job(
            workspaces=[self.job_a, self.job_b],
            period="weekly",
        )
        md = self.mod.render_markdown(data)
        self.assertIn("## Job: `job-alpha`", md)
        self.assertIn("## Job: `job-beta`", md)
        self.assertIn("feat: add Stripe webhook handler", md)
        self.assertIn("Implement Stripe webhook handler", md)
        self.assertIn("Add retry backoff policy", md)
        self.assertIn("Copy-Paste Standup", md)

    def test_cli_writes_obsidian_and_stdout(self):
        script_path = os.path.join(ROOT, "skills", "pulse-report", "scripts", "pulse_report.py")
        vault_dir = os.path.join(self.tmp.name, "vault")
        proc = subprocess.run(
            [
                sys.executable, script_path,
                "--workspace", self.job_a,
                "--workspace", self.job_b,
                "--period", "daily",
                "--vault", vault_dir,
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("job-alpha", proc.stdout)
        self.assertIn("job-beta", proc.stdout)
        # Verify Obsidian note was written in vault_dir
        files = os.listdir(vault_dir)
        self.assertTrue(any(f.startswith("pulse-daily-") for f in files))


if __name__ == "__main__":
    unittest.main()

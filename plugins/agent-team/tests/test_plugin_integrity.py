import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

from _load import ROOT


def find_bash():
    if os.name == "nt":
        for cand in [r"C:\Program Files\Git\bin\bash.exe", r"C:\Program Files\Git\usr\bin\bash.exe"]:
            if os.path.isfile(cand):
                return cand
    b = shutil.which("bash")
    return b or "bash"


def frontmatter(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    return (m.group(1) if m else ""), text


class PluginIntegrity(unittest.TestCase):
    def test_all_skills_have_valid_frontmatter_and_under_800_lines(self):
        skills_dir = os.path.join(ROOT, "skills")
        found = sorted(d for d in os.listdir(skills_dir)
                       if os.path.isfile(os.path.join(skills_dir, d, "SKILL.md")))
        self.assertIn("market-recon", found)
        self.assertIn("product-launch", found)
        for s in found:
            path = os.path.join(skills_dir, s, "SKILL.md")
            fm, text = frontmatter(path)
            self.assertIn("name: %s\n" % s, fm + "\n", s)
            self.assertRegex(fm, r"description:", s)
            self.assertLessEqual(len(text.splitlines()), 800, s)

    def test_all_agents_under_800_lines_and_skill_paths_resolve(self):
        agents_dir = os.path.join(ROOT, "agents")
        for fn in sorted(os.listdir(agents_dir)):
            if not fn.endswith(".md"):
                continue
            path = os.path.join(agents_dir, fn)
            fm, text = frontmatter(path)
            self.assertLessEqual(len(text.splitlines()), 800, fn)
            for m in re.finditer(r"^- `(/[^`]+/SKILL\.md)`", text, re.M):
                skill_path = m.group(1)
                self.assertTrue(os.path.isfile(skill_path),
                                "%s references missing skill %s" % (fn, skill_path))
            in_skills = False
            for line in fm.splitlines():
                if re.match(r"^skills:\s*$", line):
                    in_skills = True
                    continue
                if in_skills:
                    m = re.match(r"^\s*-\s*([a-z0-9-]+)\s*$", line)
                    if m:
                        s_name = m.group(1)
                        s_path = os.path.join(ROOT, "skills", s_name, "SKILL.md")
                        self.assertTrue(os.path.isfile(s_path),
                                        "%s frontmatter references missing skill %s" % (fn, s_name))
                    else:
                        in_skills = False

    def test_package_1_ui_contrast_and_visual_diff_wired(self):
        self.assertTrue(os.path.isfile(
            os.path.join(ROOT, "skills", "design-intelligence", "scripts", "contrast.py")))
        self.assertTrue(os.path.isfile(
            os.path.join(ROOT, "skills", "design-intelligence", "references", "tokens.json")))
        self.assertTrue(os.path.isfile(
            os.path.join(ROOT, "skills", "browser-verify", "scripts", "imgdiff.py")))
        self.assertTrue(os.path.isfile(
            os.path.join(ROOT, "skills", "browser-verify", "references", "e2e.example.spec.ts")))
        _, di_text = frontmatter(os.path.join(ROOT, "skills", "design-intelligence", "SKILL.md"))
        self.assertIn("contrast.py", di_text)
        self.assertIn("tokens.json", di_text)
        _, bv_text = frontmatter(os.path.join(ROOT, "skills", "browser-verify", "SKILL.md"))
        self.assertIn("imgdiff.py", bv_text)
        self.assertIn("e2e.example.spec.ts", bv_text)

    def test_package_2_market_recon_wired(self):
        for rel in (
            ("skills", "market-recon", "SKILL.md"),
            ("skills", "market-recon", "scripts", "reviews.py"),
            ("skills", "market-recon", "references", "themes.json"),
            ("skills", "market-recon", "references", "features.csv"),
        ):
            self.assertTrue(os.path.isfile(os.path.join(ROOT, *rel)), "/".join(rel))
        _, mr_text = frontmatter(os.path.join(ROOT, "skills", "market-recon", "SKILL.md"))
        self.assertIn("S01", mr_text)
        self.assertIn("F01", mr_text)
        _, analyst_text = frontmatter(os.path.join(ROOT, "agents", "analyst.md"))
        self.assertIn("market-recon", analyst_text)
        _, pm_text = frontmatter(os.path.join(ROOT, "agents", "pm.md"))
        self.assertIn("market-recon", pm_text)

    def test_package_3_gates_sweep_and_parity(self):
        run_gates = os.path.join(ROOT, "scripts", "run-gates.sh")
        with open(run_gates, encoding="utf-8") as fh:
            gates_text = fh.read()
        self.assertLessEqual(len(gates_text.splitlines()), 800)
        self.assertIn("run_brand_sweep", gates_text)
        self.assertIn("run_parity_check", gates_text)

        # Functional test of run-gates.sh on a temp directory with brand.json and features.csv
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "docs"), exist_ok=True)
            os.makedirs(os.path.join(d, "src"), exist_ok=True)
            with open(os.path.join(d, "docs", "brand.json"), "w") as fh:
                json.dump({"avoid": ["Calendly"]}, fh)
            with open(os.path.join(d, "src", "app.ts"), "w") as fh:
                fh.write("export const title = 'Calendly clone';\n")
            res = subprocess.run([find_bash(), run_gates], cwd=d, capture_output=True, text=True)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("brand sweep", res.stdout)

            # Fix the brand violation, add a failing must-have in docs/features.csv
            with open(os.path.join(d, "src", "app.ts"), "w") as fh:
                fh.write("export const title = 'Slotwise';\n")
            with open(os.path.join(d, "docs", "features.csv"), "w") as fh:
                fh.write("feature,area,priority,original,clone,notes\n"
                         "Book slot,booking,must,yes,no,\n")
            res2 = subprocess.run([find_bash(), run_gates], cwd=d, capture_output=True, text=True)
            self.assertNotEqual(res2.returncode, 0)
            self.assertIn("feature parity", res2.stdout)

            # Mark the must-have as done -> both gates pass
            with open(os.path.join(d, "docs", "features.csv"), "w") as fh:
                fh.write("feature,area,priority,original,clone,notes\n"
                         "Book slot,booking,must,yes,yes,\n")
            res3 = subprocess.run([find_bash(), run_gates], cwd=d, capture_output=True, text=True)
            self.assertEqual(res3.returncode, 0, res3.stdout + res3.stderr)
            self.assertIn("Gate PASSED: brand sweep", res3.stdout)
            self.assertIn("Gate PASSED: feature parity", res3.stdout)

    def test_package_4_saas_integrations_wired(self):
        ref = os.path.join(ROOT, "skills", "backend-discipline", "references", "saas-integrations.md")
        self.assertTrue(os.path.isfile(ref))
        _, bd_text = frontmatter(os.path.join(ROOT, "skills", "backend-discipline", "SKILL.md"))
        self.assertIn("references/saas-integrations.md", bd_text)
        _, bi_text = frontmatter(os.path.join(ROOT, "agents", "backend-implementer.md"))
        self.assertIn("saas-integrations.md", bi_text)

    def test_package_5_product_launch_wired(self):
        for rel in (
            ("skills", "product-launch", "SKILL.md"),
            ("skills", "product-launch", "scripts", "listing.py"),
            ("skills", "product-launch", "references", "listing.example.json"),
            ("skills", "product-launch", "references", "preflight.md"),
            ("skills", "product-launch", "references", "brand-and-trademark.md"),
        ):
            self.assertTrue(os.path.isfile(os.path.join(ROOT, *rel)), "/".join(rel))
        ship_cmd = os.path.join(ROOT, "commands", "ship.md")
        ship_skill = os.path.join(ROOT, "skills", "ship", "SKILL.md")
        ship_path = ship_cmd if os.path.isfile(ship_cmd) else ship_skill
        _, ship_text = frontmatter(ship_path)
        self.assertIn("product-launch", ship_text)


if __name__ == "__main__":
    unittest.main()

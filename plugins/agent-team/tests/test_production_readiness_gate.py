import tempfile
import unittest
from pathlib import Path
import sys

SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import production_readiness_gate  # noqa: E402


class TestProductionReadinessGate(unittest.TestCase):
    def test_detects_silent_exception_and_unbounded_timeout_in_python(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            p = ws / "service.py"
            p.write_text(
                "import requests\n\n"
                "def sync_orders():\n"
                "    try:\n"
                "        resp = requests.post('https://api.example.com/orders')\n"
                "    except Exception:\n"
                "        pass\n",
                encoding="utf-8",
            )
            rep = production_readiness_gate.scan_workspace_prr(ws)
            kinds = [f["kind"] for f in rep["findings"]]
            self.assertIn("silent_exception_swallow", kinds)
            self.assertIn("unbounded_network_timeout", kinds)

    def test_detects_hollow_todo_and_hardcoded_localhost_and_empty_catch(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            p = ws / "client.ts"
            p.write_text(
                "// TODO: wire real payment gateway before launch\n"
                "export async function checkout() {\n"
                "  try {\n"
                "    await fetch('http://localhost:4000/pay');\n"
                "  } catch (err) {}\n"
                "}\n",
                encoding="utf-8",
            )
            rep = production_readiness_gate.scan_workspace_prr(ws)
            kinds = [f["kind"] for f in rep["findings"]]
            self.assertIn("hollow_demo_marker", kinds)
            self.assertIn("hardcoded_localhost_origin", kinds)
            self.assertIn("silent_exception_swallow", kinds)

    def test_clean_production_file_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            p = ws / "clean_service.py"
            p.write_text(
                "import os\nimport requests\n\n"
                "def fetch_status():\n"
                "    url = os.getenv('API_URL', 'https://api.example.com')\n"
                "    try:\n"
                "        return requests.get(url, timeout=5.0).status_code\n"
                "    except requests.RequestException as exc:\n"
                "        raise RuntimeError('Upstream failed') from exc\n",
                encoding="utf-8",
            )
            rep = production_readiness_gate.scan_workspace_prr(ws)
            self.assertEqual(rep["finding_count"], 0)


if __name__ == "__main__":
    unittest.main()

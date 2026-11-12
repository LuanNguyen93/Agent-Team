import unittest
from pathlib import Path
import tempfile
import sys

SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import context_kernel  # noqa: E402


class TestContextKernel(unittest.TestCase):
    def test_skeletonize_python_file_reduces_tokens(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "sample.py"
            body_lines = "\n".join([f"        x_{i} = {i} * 2" for i in range(60)])
            p.write_text(
                f'class OrderEngine:\n'
                f'    """Processes enterprise orders."""\n'
                f'    def compute_total(self, items: list, tax: float) -> float:\n'
                f'        """Computes total price with tax."""\n'
                f'{body_lines}\n'
                f'        return 0.0\n',
                encoding="utf-8",
            )
            skel = context_kernel.skeletonize_python_file(p, "sample.py")
            self.assertIsNotNone(skel)
            self.assertGreater(skel.reduction_pct, 65.0)
            names = [s.name for s in skel.symbols]
            self.assertIn("OrderEngine", names)
            self.assertIn("OrderEngine.compute_total", names)

    def test_extract_symbol_source_surgical(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "service.py"
            filler = "\n".join([f"CONST_{i} = {i}" for i in range(100)])
            p.write_text(
                f"{filler}\n\n"
                f"def target_fn(a: int, b: int) -> int:\n"
                f"    return a + b\n",
                encoding="utf-8",
            )
            res = context_kernel.extract_symbol_source(p, "target_fn")
            self.assertIsNotNone(res)
            self.assertEqual(res["symbol"], "target_fn")
            self.assertIn("def target_fn", res["source"])
            self.assertGreater(res["reduction_pct"], 80.0)

    def test_compress_log_output_drops_noise(self):
        passing_lines = [f"test_case_{i} ... ok" for i in range(120)]
        failing_block = [
            "FAIL: test_payment_idempotency (tests.TestPayments)",
            "Traceback (most recent call last):",
            '  File "test_payments.py", line 42, in test_payment_idempotency',
            "AssertionError: 500 != 200",
            "Ran 121 tests in 1.42s",
            "FAILED (failures=1)",
        ]
        raw_log = "\n".join(passing_lines + failing_block)
        res = context_kernel.compress_log_output(raw_log)
        self.assertGreater(res["reduction_pct"], 75.0)
        self.assertIn("AssertionError: 500 != 200", res["output"])
        self.assertIn("FAILED (failures=1)", res["output"])
        self.assertNotIn("test_case_50 ... ok", res["output"])


if __name__ == "__main__":
    unittest.main()

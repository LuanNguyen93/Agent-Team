import tempfile
import unittest
from pathlib import Path
import importlib.util

SCRIPT_PATH = (
    Path(__file__).resolve().parent.parent
    / "skills"
    / "design-intelligence"
    / "scripts"
    / "bio_design_gate.py"
)
spec = importlib.util.spec_from_file_location("bio_design_gate", SCRIPT_PATH)
bio_design_gate = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(bio_design_gate)


class TestBioDesignGate(unittest.TestCase):
    def test_init_and_audit_clean_prototype(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            proto = ws / "docs" / "prototype.html"
            rc_init = bio_design_gate.main(
                [str(ws), "--init-prototype", str(proto), "--title", "Bio Dashboard"]
            )
            self.assertEqual(rc_init, 0)
            self.assertTrue(proto.exists())

            findings = bio_design_gate.audit_prototype_file(proto)
            self.assertEqual(findings, [])

    def test_archetype_prototype_generation_and_audit(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            proto = ws / "docs" / "prototype.html"
            rc_init = bio_design_gate.main(
                [
                    str(ws),
                    "--init-prototype",
                    str(proto),
                    "--archetype",
                    "monolithic-precision",
                    "--title",
                    "Precision Terminal",
                ]
            )
            self.assertEqual(rc_init, 0)
            html = proto.read_text(encoding="utf-8")
            self.assertIn('data-archetype="monolithic-precision"', html)
            for arch in (
                "swiss-editorial",
                "monolithic-precision",
                "rams-industrial",
                "shibui-organic",
                "kinetic-atelier",
            ):
                self.assertIn(f'data-set-archetype="{arch}"', html)
            self.assertIn("asymmetric-stage", html)
            self.assertIn("7fr 5fr", html)
            self.assertIn("hairline-ledger", html)
            self.assertIn("--specular-rim", html)
            self.assertEqual(bio_design_gate.audit_prototype_file(proto), [])

    def test_detects_halation_risk_in_tokens(self):
        with tempfile.TemporaryDirectory() as tmp:
            tok = Path(tmp) / "tokens.json"
            tok.write_text(
                '{"color": {"text": "#000000", "bg": "#ffffff"}, "motion": {"ease": "cubic-bezier(0.22,1,0.36,1)"}}',
                encoding="utf-8",
            )
            findings = bio_design_gate.audit_tokens_bio(tok)
            kinds = [f["kind"] for f in findings]
            self.assertIn("photobiology_halation_risk", kinds)

    def test_detects_ai_slop_and_linear_motion(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            bad_ui = ws / "Hero.tsx"
            bad_ui.write_text(
                'export const Hero = () => <div className="bg-gradient-to-r from-indigo-500 via-purple-500 to-pink-500" style={{transition: "all 0.3s linear"}} />;\n',
                encoding="utf-8",
            )
            findings = bio_design_gate.scan_ui_files_for_slop(ws)
            kinds = [f["kind"] for f in findings]
            self.assertIn("ai_slop_purple_neon_gradient", kinds)
            self.assertIn("robotic_linear_motion", kinds)

    def test_detects_static_card_hover_float_cliche(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            bad_css = ws / "styles.css"
            bad_css.write_text(
                ".card:hover { transform: translateY(-4px); }\n"
                ". interactive-btn:hover { transform: translateY(-2px); /* allow-hover-lift */ }\n",
                encoding="utf-8",
            )
            bad_tsx = ws / "Panel.tsx"
            bad_tsx.write_text(
                'export const Panel = () => <div className="card rounded-xl border p-6 hover:-translate-y-1">Static</div>;\n',
                encoding="utf-8",
            )
            findings = bio_design_gate.scan_ui_files_for_slop(ws)
            float_findings = [
                f for f in findings if f["kind"] == "static_card_hover_float_cliche"
            ]
            self.assertEqual(len(float_findings), 2)

    def test_detects_symmetric_card_soup_slop(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            bad_grid = ws / "dashboard.css"
            bad_grid.write_text(
                ".kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); }\n"
                ".gallery-grid { grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); /* allow-uniform-grid */ }\n",
                encoding="utf-8",
            )
            findings = bio_design_gate.scan_ui_files_for_slop(ws)
            soup_findings = [
                f for f in findings if f["kind"] == "symmetric_card_soup_slop"
            ]
            self.assertEqual(len(soup_findings), 1)

    def test_detects_negative_energy_copy_and_missing_share_joy(self):
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            bad_proto = ws / "docs" / "prototype.html"
            bad_proto.parent.mkdir(parents=True, exist_ok=True)
            bad_proto.write_text(
                '<html data-env="studio" data-state="populated">'
                '<style>@media (prefers-reduced-motion: reduce) {}</style>'
                '<div data-state="populated"><h1>FATAL ERROR</h1></div>'
                '<div data-state="loading"></div><div data-state="empty"></div><div data-state="error"></div>'
                '<button data-set-env="daylight"></button><button data-set-env="studio"></button><button data-set-env="night"></button>'
                '</html>',
                encoding="utf-8",
            )
            findings = bio_design_gate.audit_prototype_file(bad_proto)
            kinds = [f["kind"] for f in findings]
            self.assertIn("missing_shared_positivity_affordance", kinds)
            self.assertIn("negative_energy_punitive_copy", kinds)


if __name__ == "__main__":
    unittest.main()

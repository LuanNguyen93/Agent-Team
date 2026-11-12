#!/usr/bin/env python3
"""
Bio-Adaptive & Eudaimonic (Positive Energy) Design Gate for Agent Team.

Solves the Full-Stack Frontend Design-to-Production & Emotional Energy Gap:
1. Interactive Human-Reviewable Prototype Generator (`--init-prototype`):
   Generates a self-contained `docs/prototype.html` from `docs/tokens.json`
   featuring a live Human Review HUD and grounded in:
   - Neuro-Ergonomics (Anti-halation contrast, 65ch foveal span, 44px Fitts targets, spring physics)
   - Positive Design Philosophy (Desmet & Pohlmeyer's Pleasure + Personal Significance + Virtue/Sharing,
     Don Norman's Emotional Design, Ingrid Fetell Lee's Aesthetics of Joy)
   - 4 Compassionate UX States (Populated with Shared Joy, Calm Loading, Uplifting Empty Canvas, Safe Recovery Error)
   - 3 Sunlit & Hearth Bio-Environments (Sunlit Daylight, Warm Studio, Golden Hearth Night)
2. Neuro-Ergonomic, Anti-AI-Slop & Positive-Energy Auditor (`audit` default mode):
   - Photobiology / Anti-Halation check (4.5:1 <= ratio <= 19.5:1).
   - Anti-AI-Slop Detector (blocks neon purple/indigo gradient clichés & linear motion).
   - Anti-Negative-Energy Microcopy Detector (flags punitive/blaming all-caps state copy like
     "FATAL ERROR", "NO DATA FOUND", "OPERATION FAILED").
   - Eudaimonic Shared-Positivity Gate: Verifies that `docs/prototype.html` includes
     an interactive positivity/milestone sharing affordance (`data-eudaimonia="share-joy"`).

Zero third-party dependencies (Python standard library only).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

HEX_RE = re.compile(r"^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")

AI_SLOP_PATTERNS = [
    (
        "ai_slop_purple_neon_gradient",
        re.compile(
            r"(from-indigo-[456]00\s+via-purple-[456]00|from-purple-[456]00\s+to-pink-[456]00|"
            r"linear-gradient\([^)]*(?:#6366f1|#8b5cf6|#a855f7|#d946ef)[^)]*\))",
            re.IGNORECASE,
        ),
        "Neon indigo/purple/pink gradient cliché detected (classic 'AI slop' signature).",
    ),
    (
        "robotic_linear_motion",
        re.compile(
            r"transition(?:-timing-function)?\s*:\s*[^;}\n]*\blinear\b",
            re.IGNORECASE,
        ),
        "Mechanical 'linear' CSS transition detected; biological eyes expect spring/deceleration curves (e.g. cubic-bezier(0.22, 1, 0.36, 1)).",
    ),
    (
        "negative_energy_punitive_copy",
        re.compile(
            r">\s*(?:FATAL ERROR|OPERATION FAILED|NO DATA FOUND|INVALID INPUT|SYSTEM FAILURE)\s*<",
        ),
        "Hostile/punitive UI microcopy detected. Positive Design requires calm, reassuring, human-centered language.",
    ),
]

REQUIRED_PROTOTYPE_STATES = ("populated", "loading", "empty", "error")
REQUIRED_ENV_MODES = ("daylight", "studio", "night")


def parse_hex(value: str) -> Tuple[int, int, int]:
    m = HEX_RE.match(value.strip())
    if not m:
        raise ValueError(f"Invalid hex color: {value}")
    h = m.group(1)
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def relative_luminance(rgb: Tuple[int, int, int]) -> float:
    def channel(c: int) -> float:
        v = c / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(fg_hex: str, bg_hex: str) -> float:
    l1 = relative_luminance(parse_hex(fg_hex))
    l2 = relative_luminance(parse_hex(bg_hex))
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def audit_tokens_bio(tokens_path: Path) -> List[Dict[str, object]]:
    findings: List[Dict[str, object]] = []
    try:
        data = json.loads(tokens_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [{"kind": "token_parse_error", "file": str(tokens_path), "message": str(exc)}]

    colors = data.get("color", {})
    text_hex = colors.get("text")
    bg_hex = colors.get("bg")
    if isinstance(text_hex, str) and isinstance(bg_hex, str):
        if HEX_RE.match(text_hex) and HEX_RE.match(bg_hex):
            ratio = contrast_ratio(text_hex, bg_hex)
            if ratio > 19.5:
                findings.append(
                    {
                        "kind": "photobiology_halation_risk",
                        "file": str(tokens_path),
                        "ratio": round(ratio, 2),
                        "message": (
                            f"Primary text/bg contrast is {ratio:.2f}:1 ({text_hex} on {bg_hex}). "
                            "Extreme >19.5:1 pure black/white contrast causes retinal halation "
                            "(astigmatism blur). Use sunlit alabaster (#FAF8F5) and warm espresso ink (#1C1917)."
                        ),
                    }
                )
            elif ratio < 4.5:
                findings.append(
                    {
                        "kind": "wcag_aa_failure",
                        "file": str(tokens_path),
                        "ratio": round(ratio, 2),
                        "message": f"Primary text/bg contrast is {ratio:.2f}:1 (< 4.5:1 minimum).",
                    }
                )

    motion = data.get("motion", {})
    ease = str(motion.get("ease", ""))
    if "linear" in ease.lower():
        findings.append(
            {
                "kind": "robotic_motion_token",
                "file": str(tokens_path),
                "message": "Motion token uses mechanical 'linear' easing instead of natural spring/deceleration curve.",
            }
        )
    return findings


def audit_prototype_file(proto_path: Path) -> List[Dict[str, object]]:
    findings: List[Dict[str, object]] = []
    if not proto_path.exists():
        return [
            {
                "kind": "missing_interactive_prototype",
                "file": str(proto_path),
                "message": "Interactive human-reviewable prototype (`docs/prototype.html`) is missing.",
            }
        ]

    content = proto_path.read_text(encoding="utf-8", errors="replace")
    for state in REQUIRED_PROTOTYPE_STATES:
        if f'data-state="{state}"' not in content and f"'{state}'" not in content:
            findings.append(
                {
                    "kind": "missing_prototype_state",
                    "file": str(proto_path),
                    "state": state,
                    "message": f"Prototype is missing interactive state view '{state}'.",
                }
            )

    for env in REQUIRED_ENV_MODES:
        if f'data-env="{env}"' not in content and f"'{env}'" not in content:
            findings.append(
                {
                    "kind": "missing_circadian_mode",
                    "file": str(proto_path),
                    "env": env,
                    "message": f"Prototype is missing bio-adaptive ambient mode '{env}'.",
                }
            )

    if 'data-eudaimonia="share-joy"' not in content:
        findings.append(
            {
                "kind": "missing_shared_positivity_affordance",
                "file": str(proto_path),
                "message": "Prototype lacks a Positive Design shared-joy/gratitude affordance (`data-eudaimonia=\"share-joy\"`).",
            }
        )

    if "prefers-reduced-motion" not in content:
        findings.append(
            {
                "kind": "missing_vestibular_guard",
                "file": str(proto_path),
                "message": "Prototype lacks `@media (prefers-reduced-motion: reduce)` vestibular guard.",
            }
        )

    for kind, regex, msg in AI_SLOP_PATTERNS:
        if regex.search(content):
            findings.append({"kind": kind, "file": str(proto_path), "message": msg})

    return findings


def scan_ui_files_for_slop(root: Path) -> List[Dict[str, object]]:
    findings: List[Dict[str, object]] = []
    skip_dirs = {".git", "node_modules", "dist", "build", ".next", "__pycache__", "archive"}
    ui_exts = {".css", ".tsx", ".jsx", ".html", ".vue", ".svelte"}

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in skip_dirs]
        for fname in sorted(filenames):
            fpath = Path(dirpath) / fname
            if fpath.suffix not in ui_exts:
                continue
            try:
                text = fpath.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            rel = str(fpath.relative_to(root)).replace("\\", "/")
            for kind, regex, msg in AI_SLOP_PATTERNS:
                m = regex.search(text)
                if m:
                    line_no = text[: m.start()].count("\n") + 1
                    findings.append(
                        {"kind": kind, "file": rel, "line": line_no, "message": msg}
                    )
    return findings


def generate_prototype_html(title: str, tokens: Optional[dict] = None) -> str:
    colors = (tokens or {}).get("color", {})
    bg = colors.get("bg", "#FAF8F5")
    if bg.lower() == "#ffffff":
        bg = "#FAF8F5"
    surface = colors.get("surface", "#FFFFFF")
    text = colors.get("text", "#1C1917")
    text_muted = colors.get("text-muted", "#57534E")
    accent = colors.get("accent", "#0D9488")
    joy_warm = "#D97706"
    border = colors.get("border", "#E7E5E4")

    return f"""<!DOCTYPE html>
<html lang="en" data-env="studio" data-state="populated">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>{title} — Bio-Adaptive &amp; Eudaimonic Prototype</title>
  <style>
    /* Sunlit Warmth & Biophilic Positive Palette (Desmet, Norman & Fetell Lee) */
    :root, [data-env="studio"] {{
      --bg: {bg};
      --surface: {surface};
      --surface-warm: #FEF3C7;
      --text: {text};
      --text-muted: {text_muted};
      --accent: {accent};
      --joy-accent: {joy_warm};
      --border: {border};
      --recovery-amber: #B45309;
      --radius-outer: 18px;
      --pad-card: 22px;
      --radius-inner: 10px; /* Concentric curvature: R_outer - pad_optical */
      --spring-ease: cubic-bezier(0.22, 1, 0.36, 1);
    }}
    /* Sunlit Daylight: Crisp biophilic clarity */
    [data-env="daylight"] {{
      --bg: #F5F3EF;
      --surface: #FFFFFF;
      --surface-warm: #FDE68A;
      --text: #18181B;
      --text-muted: #52525B;
      --accent: #0F766E;
      --joy-accent: #B45309;
      --border: #D6D3D1;
    }}
    /* Circadian Golden Hearth Night: Warm charcoal/espresso, zero cold dystopian blue or halation */
    [data-env="night"] {{
      --bg: #1C1917;
      --surface: #26221E;
      --surface-warm: #3B2F20;
      --text: #F5F5F4;
      --text-muted: #A8A29E;
      --accent: #2DD4BF;
      --joy-accent: #FBBF24;
      --border: #3F3934;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: Inter, system-ui, -apple-system, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
      transition: background-color 240ms var(--spring-ease), color 240ms var(--spring-ease);
      padding-bottom: 72px;
    }}
    .review-hud {{
      position: sticky;
      top: 0;
      z-index: 50;
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
      padding: 12px 24px;
      background: var(--surface);
      border-bottom: 1px solid var(--border);
    }}
    .hud-group {{ display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }}
    .hud-label {{ font-size: 12px; font-weight: 600; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.04em; }}
    .hud-btn {{
      min-height: 40px;
      padding: 8px 14px;
      border-radius: var(--radius-inner);
      border: 1px solid var(--border);
      background: var(--bg);
      color: var(--text);
      font-size: 13px;
      font-weight: 500;
      cursor: pointer;
      transition: transform 120ms var(--spring-ease), background-color 160ms var(--spring-ease);
    }}
    .hud-btn[aria-pressed="true"] {{
      background: var(--accent);
      color: #ffffff;
      border-color: var(--accent);
    }}
    .hud-btn:focus-visible {{ outline: 2px solid var(--accent); outline-offset: 2px; }}
    .workspace {{
      max-width: 1040px;
      margin: 36px auto;
      padding: 0 24px;
    }}
    .foveal-header {{
      max-width: 65ch;
      margin-bottom: 28px;
    }}
    .foveal-header h1 {{ font-size: 28px; font-weight: 700; letter-spacing: -0.02em; margin-bottom: 8px; }}
    .foveal-header p {{ color: var(--text-muted); font-size: 16px; }}
    .kpi-grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 16px;
      margin-bottom: 24px;
    }}
    .bio-card {{
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius-outer);
      padding: var(--pad-card);
      transition: transform 180ms var(--spring-ease);
    }}
    .bio-card h2 {{ font-size: 14px; font-weight: 600; color: var(--text-muted); margin-bottom: 6px; }}
    .bio-card .metric {{ font-size: 28px; font-weight: 700; font-variant-numeric: tabular-nums; margin-bottom: 4px; }}
    .bio-card .meaning {{ font-size: 13px; color: var(--text-muted); }}
    .joy-banner {{
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      background: var(--surface);
      border: 1px solid var(--border);
      border-left: 4px solid var(--joy-accent);
      border-radius: var(--radius-outer);
      padding: var(--pad-card);
      margin-top: 20px;
    }}
    .primary-action, .joy-action {{
      min-height: 44px;
      padding: 10px 20px;
      border-radius: var(--radius-inner);
      border: none;
      background: var(--accent);
      color: #ffffff;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      transition: transform 120ms var(--spring-ease), opacity 150ms var(--spring-ease);
    }}
    .joy-action {{
      background: var(--joy-accent);
      color: #ffffff;
    }}
    .primary-action:active, .joy-action:active {{ transform: scale(0.97); }}
    .state-panel {{ display: none; }}
    [data-state="populated"] .state-populated {{ display: block; }}
    [data-state="loading"] .state-loading {{ display: block; }}
    [data-state="empty"] .state-empty {{ display: block; }}
    [data-state="error"] .state-error {{ display: block; }}
    .skeleton-bar {{
      height: 20px;
      border-radius: 8px;
      background: var(--border);
      margin-bottom: 12px;
      animation: pulse 1.8s var(--spring-ease) infinite;
    }}
    @keyframes pulse {{ 0%, 100% {{ opacity: 0.85; }} 50% {{ opacity: 0.35; }} }}
    body.show-bio-guides .primary-action,
    body.show-bio-guides .joy-action,
    body.show-bio-guides .hud-btn {{
      outline: 2px dashed #10b981 !important;
    }}
    body.show-bio-guides .foveal-header {{
      border-right: 2px dashed #f59e0b;
    }}
    @media (prefers-reduced-motion: reduce) {{
      *, *::before, *::after {{
        animation-duration: 0.01ms !important;
        transition-duration: 0.01ms !important;
      }}
    }}
  </style>
</head>
<body>
  <header class="review-hud" role="region" aria-label="Human Prototype Review Controls">
    <div class="hud-group">
      <span class="hud-label">UX State:</span>
      <button class="hud-btn" data-set-state="populated" aria-pressed="true">1. Flourishing (Populated)</button>
      <button class="hud-btn" data-set-state="loading" aria-pressed="false">2. Calm Loading</button>
      <button class="hud-btn" data-set-state="empty" aria-pressed="false">3. Fresh Canvas (Empty)</button>
      <button class="hud-btn" data-set-state="error" aria-pressed="false">4. Safe Pause (Recovery)</button>
    </div>
    <div class="hud-group">
      <span class="hud-label">Bio-Environment:</span>
      <button class="hud-btn" data-set-env="daylight" aria-pressed="false">Sunlit Daylight</button>
      <button class="hud-btn" data-set-env="studio" aria-pressed="true">Warm Studio</button>
      <button class="hud-btn" data-set-env="night" aria-pressed="false">Golden Hearth Night</button>
      <button class="hud-btn" id="toggle-guides" aria-pressed="false">Bio-Guides (65ch / 44px)</button>
    </div>
  </header>

  <main class="workspace">
    <section class="foveal-header">
      <h1>{title}</h1>
      <p>Designed for human flourishing: sunlit biophilic warmth, calm focus within a 65ch foveal span, and effortless ways to celebrate and share positive milestones together.</p>
    </section>

    <section class="state-panel state-populated" data-state="populated">
      <div class="kpi-grid">
        <article class="bio-card">
          <h2>Meaningful Progress</h2>
          <div class="metric">18 Milestones</div>
          <div class="meaning">Completed smoothly with your team this week</div>
        </article>
        <article class="bio-card">
          <h2>Team Harmony &amp; Flow</h2>
          <div class="metric">98.4%</div>
          <div class="meaning">Calm, uninterrupted creative focus time</div>
        </article>
        <article class="bio-card">
          <h2>Positive Ripple</h2>
          <div class="metric">42 Kudos</div>
          <div class="meaning">Moments of gratitude shared across peers</div>
        </article>
      </div>

      <!-- Eudaimonic Pillar 3: Virtue & Prosocial Sharing of Positivity -->
      <section class="joy-banner" data-eudaimonia="share-joy" aria-label="Share Positivity and Celebrate">
        <div style="max-width: 60ch;">
          <h2 style="font-size: 16px; color: var(--text); margin-bottom: 4px;">Share Today's Positive Energy</h2>
          <p id="joy-message" style="color: var(--text-muted); font-size: 14px;">
            Happiness grows when shared. Send a note of gratitude or share this milestone with your teammates.
          </p>
        </div>
        <div class="hud-group">
          <button class="joy-action" id="share-joy-btn">Share Positivity &amp; Celebrate</button>
          <button class="primary-action">Approve Prototype</button>
        </div>
      </section>
    </section>

    <section class="state-panel state-loading" data-state="loading" aria-busy="true">
      <p style="color: var(--text-muted); margin-bottom: 16px; max-width: 65ch;">Preparing your space with care — everything is coming together smoothly...</p>
      <div class="kpi-grid">
        <div class="bio-card"><div class="skeleton-bar" style="width: 50%"></div><div class="skeleton-bar" style="width: 80%; height: 28px"></div></div>
        <div class="bio-card"><div class="skeleton-bar" style="width: 50%"></div><div class="skeleton-bar" style="width: 80%; height: 28px"></div></div>
        <div class="bio-card"><div class="skeleton-bar" style="width: 50%"></div><div class="skeleton-bar" style="width: 80%; height: 28px"></div></div>
      </div>
    </section>

    <section class="state-panel state-empty" data-state="empty">
      <div class="bio-card" style="text-align: left; max-width: 65ch;">
        <h2 style="color: var(--text); font-size: 18px; margin-bottom: 8px;">A fresh canvas for great work</h2>
        <p style="color: var(--text-muted); margin-bottom: 16px;">Every meaningful journey begins with a first step. Start your first milestone or invite a teammate to co-create.</p>
        <button class="primary-action">Begin First Milestone</button>
      </div>
    </section>

    <section class="state-panel state-error" data-state="error" role="alert">
      <div class="bio-card" style="border-color: var(--recovery-amber); max-width: 65ch;">
        <h2 style="color: var(--recovery-amber); font-size: 18px; margin-bottom: 8px;">A gentle pause — your work is safe</h2>
        <p style="color: var(--text-muted); margin-bottom: 16px;">We couldn't reach the server just now, but your progress is safely preserved on your device. Take a breath and reconnect whenever you're ready.</p>
        <button class="primary-action">Reconnect Smoothly</button>
      </div>
    </section>
  </main>

  <script>
    document.querySelectorAll('[data-set-state]').forEach((btn) => {{
      btn.addEventListener('click', () => {{
        const state = btn.getAttribute('data-set-state');
        document.documentElement.setAttribute('data-state', state);
        document.querySelectorAll('[data-set-state]').forEach((b) =>
          b.setAttribute('aria-pressed', String(b === btn))
        );
      }});
    }});
    document.querySelectorAll('[data-set-env]').forEach((btn) => {{
      btn.addEventListener('click', () => {{
        const env = btn.getAttribute('data-set-env');
        document.documentElement.setAttribute('data-env', env);
        document.querySelectorAll('[data-set-env]').forEach((b) =>
          b.setAttribute('aria-pressed', String(b === btn))
        );
      }});
    }});
    const guideBtn = document.getElementById('toggle-guides');
    guideBtn.addEventListener('click', () => {{
      const active = document.body.classList.toggle('show-bio-guides');
      guideBtn.setAttribute('aria-pressed', String(active));
    }});
    const shareBtn = document.getElementById('share-joy-btn');
    const joyMsg = document.getElementById('joy-message');
    if (shareBtn && joyMsg) {{
      shareBtn.addEventListener('click', () => {{
        joyMsg.textContent = 'Positivity shared! Your gratitude note and milestone highlight have been sent to brighten your team\\'s feed.';
        shareBtn.textContent = 'Shared with Joy ✓';
      }});
    }}
  </script>
</body>
</html>
"""


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Bio-Adaptive & Eudaimonic Design Gate."
    )
    parser.add_argument("workspace", nargs="?", default=".", help="Workspace or file path")
    parser.add_argument(
        "--init-prototype",
        metavar="OUT_HTML",
        help="Generate an interactive bio-adaptive & eudaimonic HTML prototype at OUT_HTML",
    )
    parser.add_argument(
        "--tokens",
        metavar="TOKENS_JSON",
        help="Optional path to tokens.json for prototype generation or audit",
    )
    parser.add_argument(
        "--title",
        default="Product Surface Prototype",
        help="Title for generated prototype",
    )
    parser.add_argument("--json", action="store_true", help="Output JSON report")
    parser.add_argument(
        "--require-prototype",
        action="store_true",
        help="Fail if docs/prototype.html is missing",
    )

    args = parser.parse_args(argv)
    ws = Path(args.workspace).resolve()

    if args.init_prototype:
        out_path = Path(args.init_prototype)
        if not out_path.is_absolute():
            out_path = ws / out_path
        tokens_data = None
        tok_path = Path(args.tokens) if args.tokens else (ws / "docs" / "tokens.json")
        if tok_path.exists():
            try:
                tokens_data = json.loads(tok_path.read_text(encoding="utf-8"))
            except Exception:
                tokens_data = None
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(
            generate_prototype_html(args.title, tokens_data), encoding="utf-8"
        )
        print(f"Bio-Adaptive Prototype written to: {out_path}")
        return 0

    findings: List[Dict[str, object]] = []
    tok_path = Path(args.tokens) if args.tokens else (ws / "docs" / "tokens.json")
    if tok_path.exists():
        findings.extend(audit_tokens_bio(tok_path))

    proto_path = ws / "docs" / "prototype.html"
    ui_spec_path = ws / "docs" / "ui-spec.md"
    if args.require_prototype or proto_path.exists() or ui_spec_path.exists():
        findings.extend(audit_prototype_file(proto_path))

    if ws.is_dir():
        findings.extend(scan_ui_files_for_slop(ws))

    report = {
        "workspace": str(ws).replace("\\", "/"),
        "finding_count": len(findings),
        "findings": findings,
    }

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"Bio-Design Gate: {len(findings)} finding(s).")
        for f in findings:
            print(f"  - [{f['kind']}] {f.get('file', '')}: {f['message']}")

    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())

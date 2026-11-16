#!/usr/bin/env python3
"""
Bio-Adaptive, Eudaimonic & Supreme Art Direction Gate for Agent Team.

Solves the Full-Stack Frontend Design-to-Production, Artistic Craft & Emotional Energy Gap:
1. Interactive Human-Reviewable Prototype Generator (`--init-prototype`):
   Generates a self-contained `docs/prototype.html` from `docs/tokens.json`
   featuring a live Human Review HUD and grounded in:
   - The 6 Supreme Artistic Philosophies (Dieter Rams, Müller-Brockmann Swiss Asymmetric 7:5 Grid,
     Japanese Ma & Tufte 70% De-Boxification Hairline Ledgers, Bringhurst HDR Typography & Optical
     Gravity Padding, Jony Ive Top Specular Rim Materiality, Kowalski/Freiberg Kinetic Choreography)
   - 5 Bespoke Art Direction Archetypes (`swiss-editorial`, `monolithic-precision`, `rams-industrial`,
     `shibui-organic`, `kinetic-atelier`) with live HUD switching
   - Neuro-Ergonomics (Anti-halation contrast, 65ch foveal span, 44px Fitts targets, spring physics)
   - Positive Design Philosophy (Desmet & Pohlmeyer's Pleasure + Personal Significance + Virtue/Sharing)
   - 4 Compassionate UX States & 3 Sunlit/Hearth Bio-Environments
2. Neuro-Ergonomic, Anti-AI-Slop & Supreme Art Direction Auditor (`audit` default mode):
   - Photobiology / Anti-Halation check (4.5:1 <= ratio <= 19.5:1).
   - Anti-AI-Slop Detector (blocks neon purple/indigo gradient clichés, robotic linear motion,
     static card hover-float clichés, and equal-weight symmetric card soup).
   - Anti-Negative-Energy Microcopy Detector & Eudaimonic Shared-Positivity Gate.

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

SUPPORTED_ARCHETYPES = (
    "swiss-editorial",
    "monolithic-precision",
    "rams-industrial",
    "shibui-organic",
    "kinetic-atelier",
)

AI_SLOP_PATTERNS = [
    (
        "ai_slop_purple_neon_gradient",
        re.compile(
            r"(from-indigo-[456]00\s+via-purple-[456]00|from-purple-[456]00\s+to-pink-[456]00|"
            r"linear-gradient\([^)]*(?:#6366f1|#8b5cf6|#a855f7|#d946ef)[^)]*\))",
            re.IGNORECASE,
        ),
        "Neon indigo/purple/pink gradient cliché detected (classic 'AI slop' signature).",
        None,
    ),
    (
        "robotic_linear_motion",
        re.compile(
            r"transition(?:-timing-function)?\s*:\s*[^;}\n]*\blinear\b",
            re.IGNORECASE,
        ),
        "Mechanical 'linear' CSS transition detected; biological eyes expect spring/deceleration curves (e.g. cubic-bezier(0.22, 1, 0.36, 1)).",
        None,
    ),
    (
        "negative_energy_punitive_copy",
        re.compile(
            r">\s*(?:FATAL ERROR|OPERATION FAILED|NO DATA FOUND|INVALID INPUT|SYSTEM FAILURE)\s*<",
        ),
        "Hostile/punitive UI microcopy detected. Positive Design requires calm, reassuring, human-centered language.",
        None,
    ),
    (
        "static_card_hover_float_cliche",
        re.compile(
            r"(?:\.(?:[a-z0-9_-]*card|panel|metric-box|kpi-box|tile|surface)[a-z0-9_-]*:hover\s*\{[^}]*transform\s*:\s*translateY\(\s*-\d+(?:\.\d+)?px\s*\)"
            r"|class(?:Name)?\s*=\s*[\"'][^\"']*\b(?:card|panel|tile)\b[^\"']*\bhover:-translate-y-\d+\b)",
            re.IGNORECASE,
        ),
        "Static card hover-float cliché detected. Non-interactive containers must not levitate on hover; reserve pointer physics and :active compression for true interactive controls.",
        "allow-hover-lift",
    ),
    (
        "symmetric_card_soup_slop",
        re.compile(
            r"grid-template-columns\s*:\s*repeat\(\s*auto-(?:fit|fill)\s*,\s*minmax\(\s*2[0-6]0px\s*,\s*1fr\s*\)\s*\)",
            re.IGNORECASE,
        ),
        "Equal-weight symmetric card soup (`repeat(auto-fit, minmax(240px, 1fr))`) detected. Use an asymmetric 12-column focal split (`7fr 5fr` or `8fr 4fr`) with a single dominant anchor and a de-boxified hairline ledger.",
        "allow-uniform-grid",
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


def _find_pattern_matches(
    text: str, regex: re.Pattern, allow_marker: Optional[str]
) -> List[int]:
    lines = text.splitlines()
    matched_lines: List[int] = []
    for m in regex.finditer(text):
        line_no = text[: m.start()].count("\n") + 1
        line_str = lines[line_no - 1] if 0 < line_no <= len(lines) else ""
        if allow_marker and (allow_marker in line_str or allow_marker in m.group(0)):
            continue
        matched_lines.append(line_no)
    return matched_lines


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

    for kind, regex, msg, allow_marker in AI_SLOP_PATTERNS:
        if _find_pattern_matches(content, regex, allow_marker):
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
            for kind, regex, msg, allow_marker in AI_SLOP_PATTERNS:
                for line_no in _find_pattern_matches(text, regex, allow_marker):
                    findings.append(
                        {"kind": kind, "file": rel, "line": line_no, "message": msg}
                    )
    return findings


def generate_prototype_html(
    title: str,
    tokens: Optional[dict] = None,
    archetype: str = "shibui-organic",
) -> str:
    if archetype not in SUPPORTED_ARCHETYPES:
        archetype = "shibui-organic"
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

    arch_buttons = []
    arch_labels = {
        "swiss-editorial": "Swiss Editorial",
        "monolithic-precision": "Monolithic Precision",
        "rams-industrial": "Rams Industrial",
        "shibui-organic": "Shibui Organic",
        "kinetic-atelier": "Kinetic Atelier",
    }
    for arch_id in SUPPORTED_ARCHETYPES:
        pressed = "true" if arch_id == archetype else "false"
        arch_buttons.append(
            f'<button class="hud-btn" data-set-archetype="{arch_id}" aria-pressed="{pressed}">{arch_labels[arch_id]}</button>'
        )
    arch_buttons_html = "\n      ".join(arch_buttons)

    return f"""<!DOCTYPE html>
<html lang="en" data-env="studio" data-state="populated" data-archetype="{archetype}">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>{title} — Supreme Art Direction &amp; Bio-Adaptive Prototype</title>
  <style>
    /* Base Tokens + 5 Supreme Art Direction Archetypes (Rams, Müller-Brockmann, Hara, Tufte, Ive) */
    :root, [data-archetype="shibui-organic"] {{
      --bg: {bg};
      --surface: {surface};
      --text: {text};
      --text-muted: {text_muted};
      --accent: {accent};
      --joy-accent: {joy_warm};
      --border: {border};
      --recovery-amber: #B45309;
      --radius-outer: 16px;
      --radius-inner: 8px; /* Concentric curvature: R_outer - pad_optical */
      --font-display: "Instrument Serif", "Newsreader", Georgia, serif;
      --font-sans: Inter, system-ui, -apple-system, sans-serif;
      --font-mono: "JetBrains Mono", ui-monospace, SFMono-Regular, monospace;
      --specular-rim: inset 0 1px 0 0 rgba(255, 255, 255, 0.75);
      --shadow-ambient: 0 1px 2px rgba(28, 25, 23, 0.05), 0 12px 28px -6px rgba(28, 25, 23, 0.04);
      --spring-ease: cubic-bezier(0.22, 1, 0.36, 1);
    }}
    [data-archetype="swiss-editorial"] {{
      --bg: #FAF8F5; --surface: #FFFFFF; --text: #141413; --text-muted: #5C5954;
      --accent: #C83E2B; --joy-accent: #B45309; --border: #DFDCD4;
      --radius-outer: 2px; --radius-inner: 2px;
      --font-display: "Instrument Serif", "Playfair Display", Georgia, serif;
      --specular-rim: none; --shadow-ambient: none;
    }}
    [data-archetype="monolithic-precision"] {{
      --bg: #0B0D10; --surface: #13161C; --text: #F3F4F6; --text-muted: #8E95A2;
      --accent: #14B8A6; --joy-accent: #F59E0B; --border: #222630;
      --radius-outer: 8px; --radius-inner: 5px;
      --font-display: "Geist", Inter, system-ui, sans-serif;
      --specular-rim: inset 0 1px 0 0 rgba(255, 255, 255, 0.08);
      --shadow-ambient: 0 14px 34px -8px rgba(0, 0, 0, 0.55);
    }}
    [data-archetype="rams-industrial"] {{
      --bg: #F2EFE9; --surface: #FAF8F4; --text: #1E1E1C; --text-muted: #5A5751;
      --accent: #EA580C; --joy-accent: #0D9488; --border: #D5D1C7;
      --radius-outer: 8px; --radius-inner: 4px;
      --font-display: "IBM Plex Sans", Inter, system-ui, sans-serif;
      --specular-rim: inset 0 1px 0 0 rgba(255, 255, 255, 0.8);
      --shadow-ambient: 0 1px 2px rgba(20, 20, 19, 0.08), 0 4px 12px rgba(20, 20, 19, 0.04);
    }}
    [data-archetype="kinetic-atelier"] {{
      --bg: #F7F6F2; --surface: #FFFFFF; --text: #121214; --text-muted: #52525B;
      --accent: #2563EB; --joy-accent: #D97706; --border: #E4E4E7;
      --radius-outer: 12px; --radius-inner: 6px;
      --font-display: "Geist", Inter, system-ui, sans-serif;
      --specular-rim: inset 0 1px 0 0 rgba(255, 255, 255, 0.85);
      --shadow-ambient: 0 2px 4px rgba(18, 18, 20, 0.04), 0 16px 32px -8px rgba(18, 18, 20, 0.06);
    }}
    /* Circadian Bio-Environment Overrides */
    [data-env="daylight"] {{
      --bg: #F5F3EF; --surface: #FFFFFF; --text: #18181B; --text-muted: #52525B;
      --accent: #0F766E; --joy-accent: #B45309; --border: #D6D3D1;
    }}
    [data-env="night"] {{
      --bg: #181615; --surface: #221F1D; --text: #F5F5F4; --text-muted: #A8A29E;
      --accent: #2DD4BF; --joy-accent: #FBBF24; --border: #38332E;
      --specular-rim: inset 0 1px 0 0 rgba(255, 255, 255, 0.07);
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: var(--font-sans);
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
      transition: background-color 240ms var(--spring-ease), color 240ms var(--spring-ease);
      padding-bottom: 80px;
    }}
    .review-hud {{
      position: sticky; top: 0; z-index: 50;
      display: flex; flex-wrap: wrap; gap: 10px 18px;
      align-items: center; justify-content: space-between;
      padding: 12px 24px;
      background: var(--surface);
      border-bottom: 1px solid var(--border);
      box-shadow: var(--specular-rim);
    }}
    .hud-group {{ display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }}
    .hud-label {{
      font-family: var(--font-mono); font-size: 11px; font-weight: 600;
      color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.08em;
    }}
    .hud-btn {{
      min-height: 40px; padding: 7px 12px;
      border-radius: var(--radius-inner); border: 1px solid var(--border);
      background: var(--bg); color: var(--text);
      font-size: 12px; font-weight: 500; cursor: pointer;
      transition: transform 110ms var(--spring-ease), background-color 150ms var(--spring-ease);
    }}
    .hud-btn:active {{ transform: scale(0.985); }}
    .hud-btn[aria-pressed="true"] {{
      background: var(--accent); color: #ffffff; border-color: var(--accent);
    }}
    .hud-btn:focus-visible {{ outline: 2px solid var(--accent); outline-offset: 2px; }}
    .workspace {{ max-width: 1080px; margin: 48px auto; padding: 0 24px; }}
    .foveal-header {{ max-width: 65ch; margin-bottom: 48px; }}
    .hdr-index-label {{
      font-family: var(--font-mono); font-size: 11px; font-weight: 600;
      text-transform: uppercase; letter-spacing: 0.09em; color: var(--text-muted);
      margin-bottom: 8px; display: block;
    }}
    .foveal-header h1 {{
      font-family: var(--font-display); font-size: clamp(32px, 4vw, 44px);
      font-weight: 600; letter-spacing: -0.03em; line-height: 1.08; margin-bottom: 12px;
    }}
    .foveal-header p {{ color: var(--text-muted); font-size: 16px; }}
    /* Philosophy 2: Swiss Asymmetric 7:5 Stage (Single Dominant Focal Anchor + Hairline Ledger) */
    .asymmetric-stage {{
      display: grid;
      grid-template-columns: 7fr 5fr;
      gap: 48px;
      align-items: start;
      margin-bottom: 48px;
    }}
    @media (max-width: 768px) {{
      .asymmetric-stage {{ grid-template-columns: 1fr; gap: 32px; }}
    }}
    /* Philosophy 4 & 5: Optical Gravity Padding (20px 28px 26px) + Top Specular Rim */
    .focal-anchor {{
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius-outer);
      padding: 20px 28px 26px;
      box-shadow: var(--specular-rim), var(--shadow-ambient);
    }}
    .hdr-display-figure {{
      font-family: var(--font-display);
      font-size: clamp(44px, 5vw, 56px);
      font-weight: 600;
      letter-spacing: -0.035em;
      line-height: 1.02;
      font-variant-numeric: tabular-nums;
      margin: 8px 0 12px;
    }}
    /* Philosophy 3: Japanese Ma & De-Boxification (70% Border-Deletion Rule — Hairline Ledger) */
    .hairline-ledger {{
      display: flex;
      flex-direction: column;
    }}
    .ledger-row {{
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      gap: 16px;
      padding: 18px 0 22px; /* Optical gravity padding */
      border-top: 1px solid var(--border);
    }}
    .ledger-row:last-child {{ border-bottom: 1px solid var(--border); }}
    .ledger-value {{
      font-family: var(--font-mono);
      font-size: 20px;
      font-weight: 600;
      font-variant-numeric: tabular-nums;
    }}
    .joy-banner {{
      display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between;
      gap: 16px; padding: 20px 28px 26px;
      border-top: 1px solid var(--border);
      border-bottom: 1px solid var(--border);
    }}
    .primary-action, .joy-action {{
      min-height: 44px; padding: 10px 20px;
      border-radius: var(--radius-inner); border: none;
      background: var(--accent); color: #ffffff;
      font-size: 14px; font-weight: 600; cursor: pointer;
      transition: transform 110ms var(--spring-ease), opacity 150ms var(--spring-ease);
    }}
    .joy-action {{ background: var(--joy-accent); color: #ffffff; }}
    .primary-action:active, .joy-action:active {{ transform: scale(0.985); }}
    .state-panel {{ display: none; }}
    [data-state="populated"] .state-populated {{ display: block; }}
    [data-state="loading"] .state-loading {{ display: block; }}
    [data-state="empty"] .state-empty {{ display: block; }}
    [data-state="error"] .state-error {{ display: block; }}
    .skeleton-bar {{
      height: 20px; border-radius: 6px; background: var(--border);
      margin-bottom: 14px; animation: pulse 1.8s var(--spring-ease) infinite;
    }}
    @keyframes pulse {{ 0%, 100% {{ opacity: 0.85; }} 50% {{ opacity: 0.35; }} }}
    body.show-bio-guides .primary-action,
    body.show-bio-guides .joy-action,
    body.show-bio-guides .hud-btn {{
      outline: 2px dashed #10b981 !important;
    }}
    body.show-bio-guides .foveal-header {{ border-right: 2px dashed #f59e0b; }}
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
      <span class="hud-label">Archetype:</span>
      {arch_buttons_html}
    </div>
    <div class="hud-group">
      <span class="hud-label">UX State:</span>
      <button class="hud-btn" data-set-state="populated" aria-pressed="true">1. Flourishing</button>
      <button class="hud-btn" data-set-state="loading" aria-pressed="false">2. Calm Loading</button>
      <button class="hud-btn" data-set-state="empty" aria-pressed="false">3. Fresh Canvas</button>
      <button class="hud-btn" data-set-state="error" aria-pressed="false">4. Safe Pause</button>
    </div>
    <div class="hud-group">
      <span class="hud-label">Circadian:</span>
      <button class="hud-btn" data-set-env="daylight" aria-pressed="false">Daylight</button>
      <button class="hud-btn" data-set-env="studio" aria-pressed="true">Studio</button>
      <button class="hud-btn" data-set-env="night" aria-pressed="false">Hearth Night</button>
      <button class="hud-btn" id="toggle-guides" aria-pressed="false">Bio-Guides</button>
    </div>
  </header>

  <main class="workspace">
    <section class="foveal-header">
      <span class="hdr-index-label">01 / ART-DIRECTED SURFACE &amp; ASYMMETRIC STAGE</span>
      <h1>{title}</h1>
      <p>Engineered with a single dominant 7:5 focal anchor, de-boxified hairline ledgers (Tufte Data-Ink Ratio), HDR typographic contrast, and overhead specular materiality.</p>
    </section>

    <section class="state-panel state-populated" data-state="populated">
      <div class="asymmetric-stage">
        <article class="focal-anchor">
          <span class="hdr-index-label">PRIMARY FOCAL ANCHOR · CYCLE VELOCITY</span>
          <div class="hdr-display-figure">98.4%</div>
          <p style="color: var(--text-muted); max-width: 54ch; margin-bottom: 20px;">
            Uninterrupted creative flow sustained across 18 shipped milestones this cycle, with zero regressions.
          </p>
          <button class="primary-action">Inspect Primary Stage</button>
        </article>

        <aside class="hairline-ledger" aria-label="Secondary Telemetry Ledger">
          <div class="ledger-row" style="--i: 1">
            <div>
              <span class="hdr-index-label">01 · MEANINGFUL MILESTONES</span>
              <span style="color: var(--text-muted); font-size: 14px;">Completed smoothly with your team</span>
            </div>
            <span class="ledger-value">18</span>
          </div>
          <div class="ledger-row" style="--i: 2">
            <div>
              <span class="hdr-index-label">02 · SHARED GRATITUDE</span>
              <span style="color: var(--text-muted); font-size: 14px;">Peer kudos &amp; positive notes</span>
            </div>
            <span class="ledger-value">42</span>
          </div>
          <div class="ledger-row" style="--i: 3">
            <div>
              <span class="hdr-index-label">03 · P99 LATENCY BUDGET</span>
              <span style="color: var(--text-muted); font-size: 14px;">Sub-frame kinetic response</span>
            </div>
            <span class="ledger-value">14ms</span>
          </div>
        </aside>
      </div>

      <!-- Eudaimonic Pillar 3: Virtue & Prosocial Sharing of Positivity -->
      <section class="joy-banner" data-eudaimonia="share-joy" aria-label="Share Positivity and Celebrate">
        <div style="max-width: 60ch;">
          <span class="hdr-index-label">EUDAIMONIC SHARING · BROADEN-AND-BUILD</span>
          <p id="joy-message" style="color: var(--text); font-size: 15px;">
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
      <p style="color: var(--text-muted); margin-bottom: 24px; max-width: 65ch;">Preparing your asymmetric workspace with care...</p>
      <div class="asymmetric-stage">
        <div class="focal-anchor">
          <div class="skeleton-bar" style="width: 35%"></div>
          <div class="skeleton-bar" style="width: 65%; height: 48px"></div>
          <div class="skeleton-bar" style="width: 85%"></div>
        </div>
        <div class="hairline-ledger">
          <div class="ledger-row"><div class="skeleton-bar" style="width: 70%"></div></div>
          <div class="ledger-row"><div class="skeleton-bar" style="width: 60%"></div></div>
        </div>
      </div>
    </section>

    <section class="state-panel state-empty" data-state="empty">
      <div class="focal-anchor" style="max-width: 65ch;">
        <span class="hdr-index-label">FRESH CANVAS · ZERO STATE</span>
        <h2 style="font-size: 22px; margin-bottom: 8px;">A fresh canvas for great work</h2>
        <p style="color: var(--text-muted); margin-bottom: 20px;">Every meaningful journey begins with a clear focal anchor. Initialize your first milestone or invite a collaborator.</p>
        <button class="primary-action">Begin First Milestone</button>
      </div>
    </section>

    <section class="state-panel state-error" data-state="error" role="alert">
      <div class="focal-anchor" style="border-color: var(--recovery-amber); max-width: 65ch;">
        <span class="hdr-index-label" style="color: var(--recovery-amber);">SAFE PAUSE · STATE PRESERVED</span>
        <h2 style="color: var(--recovery-amber); font-size: 22px; margin-bottom: 8px;">A gentle pause — your work is safe</h2>
        <p style="color: var(--text-muted); margin-bottom: 20px;">We couldn't reach the upstream service just now, but your local state is preserved intact. Reconnect whenever you are ready.</p>
        <button class="primary-action">Reconnect Smoothly</button>
      </div>
    </section>
  </main>

  <script>
    document.querySelectorAll('[data-set-archetype]').forEach((btn) => {{
      btn.addEventListener('click', () => {{
        const arch = btn.getAttribute('data-set-archetype');
        document.documentElement.setAttribute('data-archetype', arch);
        document.querySelectorAll('[data-set-archetype]').forEach((b) =>
          b.setAttribute('aria-pressed', String(b === btn))
        );
      }});
    }});
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
        description="Bio-Adaptive, Eudaimonic & Supreme Art Direction Gate."
    )
    parser.add_argument("workspace", nargs="?", default=".", help="Workspace or file path")
    parser.add_argument(
        "--init-prototype",
        metavar="OUT_HTML",
        help="Generate an interactive bio-adaptive & art-directed HTML prototype at OUT_HTML",
    )
    parser.add_argument(
        "--archetype",
        choices=SUPPORTED_ARCHETYPES,
        default="shibui-organic",
        help="Bespoke Art Direction archetype preset for prototype generation",
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
            generate_prototype_html(args.title, tokens_data, archetype=args.archetype),
            encoding="utf-8",
        )
        print(f"Bio-Adaptive Prototype ({args.archetype}) written to: {out_path}")
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

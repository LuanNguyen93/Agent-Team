#!/usr/bin/env python3
"""
Obsidian Second-Brain Distillation & Vault Hygiene Tool for Agent Team.

Distils architectural decisions (ADRs), root-cause analysis (RCA) lessons,
domain invariants, and reusable engineering patterns into atomic Obsidian
Flavored Markdown notes (YAML frontmatter, callouts, [[wikilinks]]) and
maintains the vault's Map of Content (00-MOC.md).

Standard library only.
"""

import argparse
import datetime
import json
import os
import re
import sys
from typing import Dict, List, Optional

VALID_TYPES = ("adr", "rca", "domain", "pattern")
VALID_CONFIDENCE = ("observed", "inferred", "assumed")


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug or "untitled"


def today_iso() -> str:
    return datetime.date.today().isoformat()


def normalize_wikilink(link: str) -> str:
    s = link.strip()
    if s.startswith("[[") and s.endswith("]]"):
        return s
    return f"[[{s}]]"


def _update_moc(vault_dir: str, note_id: str, title: str, note_type: str, domain: str) -> str:
    moc_path = os.path.join(vault_dir, "00-MOC.md")
    today = today_iso()
    entry_line = f"- [[{note_id}|{title}]] (`{note_type}` · `{domain}`)"

    if not os.path.isfile(moc_path):
        content = (
            "---\n"
            "id: 00-moc\n"
            "title: \"Second Brain Map of Content\"\n"
            "type: moc\n"
            "domain: engineering\n"
            "confidence: observed\n"
            "verified_by: \"obsidian_distill.py\"\n"
            f"created: {today}\n"
            f"updated: {today}\n"
            "tags:\n"
            "  - agent-team\n"
            "  - second-brain\n"
            "  - moc\n"
            "---\n\n"
            "# Second Brain — Map of Content\n\n"
            "> [!abstract] Living Engineering Memory\n"
            "> Atomic evergreen notes distilled from verified ADRs, RCAs, and domain invariants.\n\n"
            "## Distilled Notes\n\n"
            f"{entry_line}\n"
        )
        with open(moc_path, "w", encoding="utf-8") as fh:
            fh.write(content)
        return moc_path

    with open(moc_path, "r", encoding="utf-8") as fh:
        existing = fh.read()

    existing = re.sub(r"^updated:\s*.*$", f"updated: {today}", existing, flags=re.M)
    if f"[[{note_id}|" not in existing and f"[[{note_id}]]" not in existing:
        if not existing.endswith("\n"):
            existing += "\n"
        existing += f"{entry_line}\n"

    with open(moc_path, "w", encoding="utf-8") as fh:
        fh.write(existing)
    return moc_path


def distill_note(
    vault_dir: str,
    note_type: str,
    title: str,
    domain: str,
    summary: str,
    details: str = "",
    confidence: str = "observed",
    verified_by: str = "manual",
    links: Optional[List[str]] = None,
    tags: Optional[List[str]] = None,
) -> str:
    """Create or merge an atomic evergreen Obsidian note and update 00-MOC.md."""
    ntype = note_type.lower().strip()
    if ntype not in VALID_TYPES:
        raise ValueError(f"Invalid note_type {note_type!r}; expected one of {VALID_TYPES}")
    conf = confidence.lower().strip()
    if conf not in VALID_CONFIDENCE:
        raise ValueError(f"Invalid confidence {confidence!r}; expected one of {VALID_CONFIDENCE}")

    os.makedirs(vault_dir, exist_ok=True)
    note_id = f"{ntype}-{slugify(title)}"
    note_path = os.path.join(vault_dir, f"{note_id}.md")
    today = today_iso()

    tag_list = ["agent-team", ntype, slugify(domain)]
    for t in tags or []:
        st = slugify(t)
        if st and st not in tag_list:
            tag_list.append(st)

    norm_links = [normalize_wikilink(lk) for lk in (links or []) if lk.strip()]
    if "[[00-MOC]]" not in norm_links:
        norm_links.insert(0, "[[00-MOC]]")

    if os.path.isfile(note_path):
        with open(note_path, "r", encoding="utf-8") as fh:
            existing = fh.read()
        existing = re.sub(r"^updated:\s*.*$", f"updated: {today}", existing, flags=re.M)
        existing = re.sub(
            r"^verified_by:\s*.*$",
            f'verified_by: "{verified_by.replace(chr(34), chr(39))}"',
            existing,
            flags=re.M,
        )
        if details and details.strip() not in existing:
            if not existing.endswith("\n"):
                existing += "\n"
            existing += f"\n### Incremental Evidence ({today})\n\n{details.strip()}\n"
        for lk in norm_links:
            if lk not in existing:
                existing += f"\n- Related: {lk}\n"
        with open(note_path, "w", encoding="utf-8") as fh:
            fh.write(existing)
    else:
        tags_yaml = "\n".join(f"  - {t}" for t in tag_list)
        links_md = "\n".join(f"- {lk}" for lk in norm_links)
        safe_title = title.replace('"', "'")
        safe_verified = verified_by.replace('"', "'")
        body = (
            "---\n"
            f"id: {note_id}\n"
            f"title: \"{safe_title}\"\n"
            f"type: {ntype}\n"
            f"domain: {slugify(domain)}\n"
            f"confidence: {conf}\n"
            f"verified_by: \"{safe_verified}\"\n"
            f"created: {today}\n"
            f"updated: {today}\n"
            "tags:\n"
            f"{tags_yaml}\n"
            "---\n\n"
            f"# {title}\n\n"
            "> [!abstract] Essence\n"
            f"> {summary.strip()}\n\n"
            "## Mechanism & Invariant\n\n"
            f"{details.strip() or summary.strip()}\n\n"
            "## Verification & Evidence\n\n"
            f"- **Confidence**: `[{conf}]`\n"
            f"- **Verified by**: `{verified_by}`\n\n"
            "## Graph Links\n\n"
            f"{links_md}\n"
        )
        with open(note_path, "w", encoding="utf-8") as fh:
            fh.write(body)

    _update_moc(vault_dir, note_id, title, ntype, slugify(domain))
    return note_path


def lint_vault(vault_dir: str) -> Dict[str, object]:
    """Validate YAML frontmatter and [[wikilinks]] across all Markdown notes in vault_dir."""
    errors: List[str] = []
    files: List[str] = []
    known_targets = set()

    if not os.path.isdir(vault_dir):
        return {"vault": vault_dir, "notes": 0, "errors": [f"Vault directory not found: {vault_dir}"]}

    for fn in sorted(os.listdir(vault_dir)):
        if not fn.endswith(".md"):
            continue
        files.append(fn)
        stem = os.path.splitext(fn)[0]
        known_targets.add(stem.lower())

    required_keys = ("id:", "title:", "type:", "domain:", "confidence:", "verified_by:")

    for fn in files:
        path = os.path.join(vault_dir, fn)
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()

        m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
        if not m:
            errors.append(f"{fn}:1: missing YAML frontmatter block")
        else:
            fm = m.group(1)
            for req in required_keys:
                if req not in fm:
                    errors.append(f"{fn}:1: frontmatter missing required key '{req[:-1]}'")
            id_match = re.search(r"^id:\s*(\S+)", fm, re.M)
            if id_match:
                known_targets.add(id_match.group(1).strip().lower())

    # Second pass: verify [[wikilinks]] resolve to a known file stem or id (unless external domain placeholder)
    # and detect orphan notes (notes neither referenced in 00-MOC.md nor linking to [[00-MOC]]).
    moc_text = ""
    moc_file = os.path.join(vault_dir, "00-MOC.md")
    if os.path.isfile(moc_file):
        with open(moc_file, "r", encoding="utf-8") as fh:
            moc_text = fh.read().lower()

    for fn in files:
        path = os.path.join(vault_dir, fn)
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
        links_in_note = []
        for match in re.finditer(r"\[\[([^\]|#]+)(?:[#|][^\]]*)?\]\]", text):
            target = match.group(1).strip().lower()
            if target:
                links_in_note.append(target)
            if target and target not in known_targets and not target.startswith("domain-"):
                errors.append(f"{fn}: broken wikilink [[{match.group(1)}]]")

        stem = os.path.splitext(fn)[0].lower()
        if stem != "00-moc" and f"[[{stem}" not in moc_text and "00-moc" not in links_in_note:
            errors.append(f"{fn}: orphan note (neither linked in 00-MOC.md nor linking to [[00-MOC]])")

    return {"vault": vault_dir, "notes": len(files), "errors": errors}


def main() -> None:
    parser = argparse.ArgumentParser(description="Obsidian Second-Brain Distillation & Linter")
    parser.add_argument("--vault", default="docs/brain", help="Path to Obsidian vault or docs/brain directory")
    parser.add_argument("--lint", nargs="?", const="", default=None, help="Lint the vault (optionally pass vault path)")
    parser.add_argument("--merge", action="store_true", help="Merge into existing note if slug already exists (default behaviour)")
    parser.add_argument("--type", choices=VALID_TYPES, default="pattern", help="Note category")
    parser.add_argument("--title", help="Atomic note title")
    parser.add_argument("--domain", default="engineering", help="Business or engineering domain")
    parser.add_argument("--summary", help="One-sentence essence of the insight")
    parser.add_argument("--details", default="", help="Mechanism, causal chain, or invariant details")
    parser.add_argument("--confidence", choices=VALID_CONFIDENCE, default="observed")
    parser.add_argument("--verified-by", default="manual", help="Command or test that verified this truth")
    parser.add_argument("--link", action="append", default=[], help="Related [[wikilink]] (repeatable)")
    parser.add_argument("--tag", action="append", default=[], help="Tag to attach (repeatable)")
    args = parser.parse_args()

    if args.lint is not None:
        vault_target = args.lint if args.lint else args.vault
        report = lint_vault(vault_target)
        print(json.dumps(report, indent=2))
        sys.exit(1 if report["errors"] else 0)

    if not args.title or not args.summary:
        parser.error("--title and --summary are required when distilling a note (or pass --lint)")

    out_path = distill_note(
        vault_dir=args.vault,
        note_type=args.type,
        title=args.title,
        domain=args.domain,
        summary=args.summary,
        details=args.details,
        confidence=args.confidence,
        verified_by=args.verified_by,
        links=args.link,
        tags=args.tag,
    )
    print(out_path)


if __name__ == "__main__":
    main()

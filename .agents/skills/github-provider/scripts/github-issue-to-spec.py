#!/usr/bin/env python3
"""
Converts JSON from `gh issue view {n} --json ...` into canonical `*.spec.md`.

Usage:
  gh issue view 1234 --json number,title,body,state,labels,assignees,comments,url \
    > {plansDir}/us-1234/step-00-us-1234.issue.json
  python github-issue-to-spec.py \
    --input {plansDir}/us-1234/step-00-us-1234.issue.json \
    --output {plansDir}/us-1234/step-00-us-1234.spec.md \
    --repo {owner}/{repo}

The `--input` option also accepts `-` to read JSON from stdin.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import date
from pathlib import Path


def ensure_utf8_stdio() -> None:
    """Force UTF-8 on stdio so Windows locale (cp1252) does not break on Unicode (e.g. →)."""
    os.environ["PYTHONIOENCODING"] = "utf-8"
    for stream in (sys.stdin, sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if not callable(reconfigure):
            continue
        try:
            reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            try:
                reconfigure(errors="replace")
            except Exception:
                pass


ensure_utf8_stdio()


def load_issue(raw: str) -> dict:
    data = json.loads(raw)
    if isinstance(data, list):  # `gh issue list --json` returns an array
        data = data[0] if data else {}
    return data or {}


_AC_HEADING = re.compile(
    r"^#{1,6}\s*(crit[eé]rios?\s+de\s+aceite|acceptance\s+criteria|ac[s]?)\b",
    re.IGNORECASE,
)


def split_body(body: str) -> tuple[str, list[str]]:
    """Return (description, acceptance-criteria items).

    Splits the issue body at the first Acceptance Criteria heading, if any.
    Bullet/numbered lines under that heading become AC items.
    """
    body = (body or "").replace("\r\n", "\n").strip()
    if not body:
        return "", []

    lines = body.split("\n")
    ac_start = None
    for idx, line in enumerate(lines):
        if _AC_HEADING.match(line.strip()):
            ac_start = idx
            break

    if ac_start is None:
        return body, []

    description = "\n".join(lines[:ac_start]).strip()
    ac_items: list[str] = []
    for line in lines[ac_start + 1:]:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):  # next section ends the AC block
            break
        item = re.sub(r"^[-*+]\s+|^\d+[.)]\s+|^\[[ xX]\]\s+", "", stripped).strip()
        item = re.sub(r"^-?\s*\[[ xX]\]\s*", "", item).strip()
        if item:
            ac_items.append(item)
    return description, ac_items


def build_spec_md(issue: dict, repo: str | None) -> str:
    number = issue.get("number")
    slug = f"us-{number}" if number else "spec"
    title = (issue.get("title") or (f"US {number}" if number else "Specification")).strip()
    state = (issue.get("state") or "").lower()
    url = issue.get("url") or (
        f"https://github.com/{repo}/issues/{number}" if repo and number else ""
    )
    labels = [l.get("name") for l in (issue.get("labels") or []) if l.get("name")]
    assignees = [a.get("login") for a in (issue.get("assignees") or []) if a.get("login")]

    description, ac_items = split_body(issue.get("body") or "")

    fm = [
        "---",
        f"id: {number if number else 'null'}",
        f"slug: {slug}",
        f'title: "{title.replace(chr(34), chr(39))}"',
        "source: github",
    ]
    if state:
        fm.append(f"issueState: {state}")
    if url:
        fm.append(f'issueUrl: "{url}"')
    if labels:
        fm.append(f"labels: [{', '.join(labels)}]")
    fm.append(f"specDate: {date.today().isoformat()}")
    fm.append("---")
    fm.append("")

    body: list[str] = [f"# Specification — {title}", ""]
    meta = []
    if state:
        meta.append(f"**State:** {state}")
    if assignees:
        meta.append(f"**Assignees:** {', '.join(assignees)}")
    if labels:
        meta.append(f"**Labels:** {', '.join(labels)}")
    if meta:
        body.extend(meta)
        body.append("")

    body.append("## Description")
    body.append("")
    body.append(description or "_No description in the issue._")
    body.append("")

    body.append("## Acceptance Criteria")
    body.append("")
    if ac_items:
        for idx, ac in enumerate(ac_items, 1):
            body.append(f"- AC{idx}: {ac}")
    else:
        body.append("_No explicit acceptance criteria in the issue — extract/validate during refinement._")
    body.append("")

    comments = issue.get("comments") or []
    if comments:
        body.append("## Comments (audit)")
        body.append("")
        for c in comments:
            author = (c.get("author") or {}).get("login") or "?"
            text = (c.get("body") or "").strip()
            if text:
                body.append(f"- **{author}:** {text}")
        body.append("")

    body.append("## Notes")
    body.append("")
    body.append("_Automatically generated from gh issue view JSON (GitHub)._")
    body.append("")

    return "\n".join(fm + body)


def main() -> int:
    ensure_utf8_stdio()

    parser = argparse.ArgumentParser(description="Converts JSON from gh issue view into canonical *.spec.md")
    parser.add_argument("--input", required=True, help="Path to JSON file (gh issue view --json ...) or '-' for stdin")
    parser.add_argument("--output", required=True, help="Output path for *.spec.md")
    parser.add_argument("--repo", default="", help="owner/repo (for issueUrl when missing in JSON)")
    args = parser.parse_args()

    if args.input == "-":
        raw = sys.stdin.read()
    else:
        input_path = Path(args.input)
        if not input_path.is_file():
            print(f"Error: input file not found: {input_path}", file=sys.stderr)
            return 1
        raw = input_path.read_text(encoding="utf-8")

    try:
        issue = load_issue(raw)
    except json.JSONDecodeError as exc:
        print(f"Error: invalid JSON — {exc}", file=sys.stderr)
        return 1

    spec_md = build_spec_md(issue, args.repo or None)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(spec_md, encoding="utf-8")
    print(f"Spec written to: {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

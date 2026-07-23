#!/usr/bin/env python3
"""
validate_state -- State Hygiene assertions for a spec-to-pr-lite state.md (v7).

Usage:
    python validate_state.py <workflow-id-or-state-path>
    python validate_state.py <...> --json
"""

import json
import os
import re
import subprocess
import sys
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


AGENT_ROOT = Path(__file__).resolve().parent.parent          # .../spec-to-pr-lite
REPO_ROOT = Path(__file__).resolve().parents[4]              # repo root (.agents/skills/spec-to-pr-lite/scripts → 4 up)
PLANS_DIR = None

def load_plans_dir() -> Path:
    """Resolve plans.dir from spec-to-pr project config."""
    cfg = REPO_ROOT / ".agents" / "skills" / "shared" / "config.json"
    plans = Path(".agents") / "plans"
    if cfg.exists():
        try:
            import json as _json
            data = _json.loads(cfg.read_text(encoding="utf-8"))
            rel = (data.get("plans") or {}).get("dir") or ".agents/plans"
            plans = Path(rel)
        except Exception:
            pass
    return (REPO_ROOT / plans).resolve() if not plans.is_absolute() else plans.resolve()

REQUIRED_KEYS = ["workflowId", "us", "status", "currentStep"]
PHASE_SOFT_TIP_STEPS = set()  # No phase soft-tip steps in spec-to-pr-lite

def resolve_state_path(arg: str) -> Path:
    p = Path(arg)
    if p.exists():
        return p
    names = [arg, f"{arg}.state.md"] if not arg.endswith(".state.md") else [arg]
    plans_dir = load_plans_dir()
    if plans_dir.exists():
        for name in names:
            matches = sorted(plans_dir.glob(f"**/{name}"))
            if matches:
                return matches[0]
    return p

def extract_frontmatter(text: str) -> str:
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if not m:
        raise ValueError("frontmatter YAML (--- ... ---) not found")
    return m.group(1)

def _strip(val: str) -> str:
    return val.strip().strip('"').strip("'").strip()

def parse_frontmatter(fm: str) -> dict:
    data: dict = {}
    lines = fm.splitlines()
    i = 0
    while i < len(lines):
        raw = lines[i]
        line = raw.rstrip()
        i += 1
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", line)
        if not m:
            continue
        key, val = m.group(1), m.group(2).strip()

        if val.startswith("[") and val.endswith("]"):
            inner = val[1:-1].strip()
            data[key] = [_strip(x) for x in inner.split(",") if x.strip()] if inner else []
            continue

        if val == "" or val == "|":
            block = []
            while i < len(lines) and (lines[i].startswith(("  ", "\t")) or not lines[i].strip()):
                block.append(lines[i])
                i += 1
            data[key] = _parse_block(block) if block else val
            continue

        data[key] = _strip(val)
    return data

def _parse_block(block: list) -> dict | list:
    items = []
    nested: dict = {}
    j = 0
    while j < len(block):
        ln = block[j]
        s = ln.strip()
        j += 1
        if not s:
            continue
        lm = re.match(r"^-\s*(.*)$", s)
        if lm:
            item = lm.group(1).strip()
            pm = re.match(r"^path:\s*(.*)$", item)
            items.append(_strip(pm.group(1)) if pm else _strip(item))
            continue
        km = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", s)
        if km:
            ckey, cval = km.group(1), km.group(2).strip()
            if cval.startswith("[") and cval.endswith("]"):
                inner = cval[1:-1].strip()
                nested[ckey] = [_strip(x) for x in inner.split(",") if x.strip()] if inner else []
            elif cval == "":
                sub = []
                while j < len(block) and (block[j].startswith("    ") or not block[j].strip()):
                    sub.append(block[j].strip())
                    j += 1
                nested[ckey] = [
                    _strip(re.sub(r"^-\s*", "", x)) for x in sub if x and not x.endswith(":")
                ]
            else:
                nested[ckey] = _strip(cval)
    if items and not nested:
        return items
    return nested

def _as_int_list(val) -> list:
    out = []
    if isinstance(val, list):
        for v in val:
            try:
                out.append(int(str(v).strip()))
            except ValueError:
                pass
    return out

def git_commit_exists(sha: str) -> bool:
    try:
        r = subprocess.run(
            ["git", "cat-file", "-e", f"{sha}^{{commit}}"],
            cwd=str(REPO_ROOT),
            capture_output=True,
        )
        return r.returncode == 0
    except (OSError, FileNotFoundError):
        return True

def validate(state_path: Path) -> dict:
    errors: list[str] = []
    warnings: list[str] = []

    text = state_path.read_text(encoding="utf-8")
    fm = extract_frontmatter(text)
    data = parse_frontmatter(fm)
    fm_raw = fm

    for k in REQUIRED_KEYS:
        if k not in data:
            errors.append(f"mandatory key missing in frontmatter: {k}")

    dry_run = str(data.get("dryRun", "false")).lower() == "true"
    status = str(data.get("status", "")).strip().lower()
    closed = status in ("completed", "cancelled", "failed")
    completed = _as_int_list(data.get("completedSteps", []))

    cur_raw = data.get("currentStep")
    try:
        current = int(str(cur_raw).strip())
    except (TypeError, ValueError):
        current = None
        errors.append(f"currentStep is non-numeric: {cur_raw!r}")

    if current is not None and completed:
        mx = max(completed)
        if current not in (mx + 1, mx) and current not in completed:
            errors.append(
                f"currentStep={current} inconsistent with completedSteps "
                f"(expected {mx} or {mx + 1})"
            )

    manifest = data.get("workflowManifest", {})
    created = manifest.get("created", []) if isinstance(manifest, dict) else []
    artifacts = manifest.get("artifacts", []) if isinstance(manifest, dict) else []
    checked = 0
    if not dry_run:
        seen = set()
        for path in list(created) + list(artifacts):
            if not path or path in ("[]", "|") or path in seen:
                continue
            seen.add(path)
            checked += 1
            target = (REPO_ROOT / path).resolve()
            if not target.exists():
                msg = f"manifest file missing on disk: {path}"
                (warnings if closed else errors).append(msg)

    commit_shas = []
    for m in re.finditer(r"^\s*-?\s*sha:\s*['\"]?([0-9a-f]{7,40})", fm_raw, re.MULTILINE):
        if m.group(1) not in commit_shas:
            commit_shas.append(m.group(1))
    if not dry_run:
        for sha in commit_shas:
            if not git_commit_exists(sha):
                errors.append(f"registered commit does not exist in git: {sha}")

    return {
        "state": str(state_path),
        "workflowId": data.get("workflowId"),
        "status": data.get("status"),
        "currentStep": current,
        "dryRun": dry_run,
        "completedSteps": completed,
        "files_checked": checked,
        "commits_checked": commit_shas,
        "errors": errors,
        "warnings": warnings,
        "ok": not errors,
    }

def main():
    ensure_utf8_stdio()

    as_json = "--json" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) < 1:
        print("Usage: python validate_state.py <workflow-id-or-state-path> [--json]")
        sys.exit(1)

    state_path = resolve_state_path(args[0])
    if not state_path.exists():
        print(f"Error: state.md not found: {args[0]}")
        sys.exit(1)

    try:
        result = validate(state_path)
    except (ValueError, OSError) as exc:
        print(f"Error validating {state_path}: {exc}")
        sys.exit(1)

    if as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print("=" * 50)
        print("  validate_state (lite) -- State Hygiene (v7)")
        print("=" * 50)
        print(f"State: {result['state']}")
        print(f"Workflow: {result['workflowId']} | status: {result['status']} "
              f"| currentStep: {result['currentStep']} | dryRun: {result['dryRun']}")
        print(f"completedSteps: {result['completedSteps']}")
        print(f"Files verified: {result['files_checked']} | "
              f"commits: {len(result['commits_checked'])}")
        if result["warnings"]:
            print("\n## Warnings")
            for w in result["warnings"]:
                print(f"  ! {w}")
        if result["errors"]:
            print("\n## ERRORS")
            for e in result["errors"]:
                print(f"  x {e}")
        else:
            print("\n[OK] state is consistent with manifest and git.")

    sys.exit(0 if result["ok"] else 1)

if __name__ == "__main__":
    main()

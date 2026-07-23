#!/usr/bin/env python3
"""
Register / normalize / optionally mirror a local *.spec.md into the workflow canonical path.

Usage:
  python register_local_spec.py --input path/to/foo.spec.md [--slug SLUG]
  python register_local_spec.py --input specs/foo.spec.md --mirror
  python register_local_spec.py --input specs/foo/README.spec.md --force

Writes: {plansDir}/{slug}/step-00-{slug}.spec.md with source: local.
Optional mirror: {specs-dir}/{slug}.spec.md (flat human-browsable copy).

Supported input layouts under specsDir:
  Flat:    {specs-dir}/{slug}.spec.md
  Nested:  {specs-dir}/{slug}/README.spec.md
           {specs-dir}/{slug}/{slug}.spec.md
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


REPO_ROOT = Path(__file__).resolve().parents[4]
CONFIG_PATH = REPO_ROOT / ".agents" / "skills" / "shared" / "config.json"
DEFAULT_PLANS_DIR = ".agents/plans"
DEFAULT_SPECS_DIR = "specs"

_FM_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n?", re.DOTALL)
_SLUG_LINE = re.compile(r"^slug:\s*(.+)$", re.MULTILINE | re.IGNORECASE)
_TITLE_LINE = re.compile(r"^title:\s*(.+)$", re.MULTILINE | re.IGNORECASE)
_SOURCE_LINE = re.compile(r"^source:\s*.+$", re.MULTILINE | re.IGNORECASE)
_SPECDATE_LINE = re.compile(r"^specDate:\s*.+$", re.MULTILINE | re.IGNORECASE)


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        return {}
    try:
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def plans_dir(cfg: dict | None = None) -> Path:
    cfg = cfg if cfg is not None else load_config()
    rel = ((cfg.get("plans") or {}).get("dir") or DEFAULT_PLANS_DIR).strip()
    path = Path(rel)
    if not path.is_absolute():
        path = REPO_ROOT / path
    return path.resolve()


def specs_dir(cfg: dict | None = None) -> Path:
    cfg = cfg if cfg is not None else load_config()
    rel = ((cfg.get("plans") or {}).get("specsDir") or DEFAULT_SPECS_DIR).strip()
    path = Path(rel)
    if not path.is_absolute():
        path = REPO_ROOT / path
    return path.resolve()


def strip_quotes(val: str) -> str:
    return val.strip().strip('"').strip("'").strip()


def infer_slug_from_path(path: Path) -> str:
    """
    Infer slug from filename / one-level nested layout.
    - foo.spec.md -> foo
    - step-00-foo.spec.md -> foo
    - foo/README.spec.md -> foo (parent dir)
    - foo/foo.spec.md -> foo
    """
    name = path.name
    if name.endswith(".spec.md"):
        stem = name[: -len(".spec.md")]
    else:
        stem = path.stem

    if stem.lower() in {"readme", "index", "spec"} and path.parent != path.anchor:
        # Nested: specs/{slug}/README.spec.md
        return path.parent.name

    if stem.startswith("step-00-"):
        stem = stem[len("step-00-") :]

    # Nested twin: specs/{slug}/{slug}.spec.md
    if path.parent.name == stem:
        return stem

    return stem


def resolve_slug(text: str, path: Path, override: str | None) -> str:
    if override:
        return override.strip()
    m = _SLUG_LINE.search(text)
    if m:
        return strip_quotes(m.group(1))
    return infer_slug_from_path(path)


def infer_title(text: str, slug: str) -> str:
    m = _TITLE_LINE.search(text)
    if m:
        return strip_quotes(m.group(1))
    h1 = re.search(r"^#\s+Specification\s+[—–-]\s+(.+)$", text, re.MULTILINE)
    if h1:
        return h1.group(1).strip()
    h1b = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
    if h1b:
        return h1b.group(1).strip()
    return slug.replace("-", " ").title()


def normalize_spec(text: str, slug: str, title: str | None = None) -> str:
    """Ensure frontmatter has slug, title, source: local, and prefer today for missing specDate."""
    text = text.replace("\r\n", "\n")
    if not text.endswith("\n"):
        text += "\n"

    title = title or infer_title(text, slug)
    safe_title = title.replace('"', "'")

    fm_match = _FM_RE.match(text)
    if fm_match:
        fm = fm_match.group(1)
        body = text[fm_match.end() :]
        # slug
        if _SLUG_LINE.search(fm):
            fm = _SLUG_LINE.sub(f"slug: {slug}", fm, count=1)
        else:
            fm = f"slug: {slug}\n" + fm
        # title
        if _TITLE_LINE.search(fm):
            fm = _TITLE_LINE.sub(f'title: "{safe_title}"', fm, count=1)
        else:
            fm = f'title: "{safe_title}"\n' + fm
        # source: local (always for this provider)
        if _SOURCE_LINE.search(fm):
            fm = _SOURCE_LINE.sub("source: local", fm, count=1)
        else:
            fm = fm.rstrip() + "\nsource: local\n"
        # specDate if missing
        if not _SPECDATE_LINE.search(fm):
            fm = fm.rstrip() + f"\nspecDate: {date.today().isoformat()}\n"
        if "id:" not in fm.lower():
            fm = "id: null\n" + fm
        return f"---\n{fm.strip()}\n---\n\n{body.lstrip()}"

    # No frontmatter: synthesize
    body = text.lstrip()
    fm_lines = [
        "---",
        "id: null",
        f"slug: {slug}",
        f'title: "{safe_title}"',
        "source: local",
        f"specDate: {date.today().isoformat()}",
        "---",
        "",
    ]
    return "\n".join(fm_lines) + body


def resolve_input(path: Path, cfg: dict) -> Path:
    """Resolve input path; if bare slug, try flat + nested under specsDir."""
    if path.exists():
        return path.resolve()

    # Try relative to repo root
    cand = (REPO_ROOT / path).resolve()
    if cand.exists():
        return cand

    # Treat as slug lookup under specsDir
    slug = path.name
    if slug.endswith(".spec.md"):
        slug = slug[: -len(".spec.md")]
    if slug.startswith("step-00-"):
        slug = slug[len("step-00-") :]

    sdir = specs_dir(cfg)
    candidates = [
        sdir / f"{slug}.spec.md",
        sdir / slug / "README.spec.md",
        sdir / slug / f"{slug}.spec.md",
    ]
    for c in candidates:
        if c.is_file():
            return c.resolve()

    raise SystemExit(
        f"ERROR: input not found: {path}\n"
        f"Tried: {', '.join(str(c) for c in candidates)}"
    )


def write_if_allowed(dest: Path, content: str, force: bool) -> str:
    dest.parent.mkdir(parents=True, exist_ok=True)
    existed = dest.exists()
    if existed and not force:
        existing = dest.read_text(encoding="utf-8")
        if existing.replace("\r\n", "\n") == content.replace("\r\n", "\n"):
            return "unchanged"
        raise SystemExit(
            f"ERROR: destination exists and differs: {dest}\n"
            "Re-run with --force to overwrite, or confirm manually."
        )
    dest.write_text(content, encoding="utf-8")
    return "overwritten" if existed else "written"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Register local *.spec.md into {us-dir}/step-00-{slug}.spec.md (source: local)."
    )
    parser.add_argument(
        "--input",
        "-i",
        required=True,
        help="Path to *.spec.md, or slug to resolve under specsDir (flat or one-level nested).",
    )
    parser.add_argument("--slug", help="Override slug (default: frontmatter or path inference).")
    parser.add_argument(
        "--plans-dir",
        help="Override plans.dir (default from config.json or .agents/plans).",
    )
    parser.add_argument(
        "--specs-dir",
        help="Override plans.specsDir for slug lookup / mirror (default from config).",
    )
    parser.add_argument(
        "--mirror",
        action="store_true",
        help="Also write flat mirror {specs-dir}/{slug}.spec.md.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite destination if it exists and differs.",
    )
    parser.add_argument("--json", action="store_true", help="Machine-readable JSON output.")
    args = parser.parse_args()

    ensure_utf8_stdio()

    cfg = load_config()
    if args.plans_dir:
        cfg.setdefault("plans", {})["dir"] = args.plans_dir
    if args.specs_dir:
        cfg.setdefault("plans", {})["specsDir"] = args.specs_dir

    src = resolve_input(Path(args.input), cfg)
    raw = src.read_text(encoding="utf-8")
    slug = resolve_slug(raw, src, args.slug)
    normalized = normalize_spec(raw, slug)

    us_dir = plans_dir(cfg) / slug
    dest = us_dir / f"step-00-{slug}.spec.md"
    # When input is already the canonical step-00 path, allow in-place
    # normalize rewrite so --mirror happy path works without --force.
    same_as_dest = src.resolve() == dest.resolve()
    action = write_if_allowed(dest, normalized, force=args.force or same_as_dest)

    mirror_path = None
    mirror_action = None
    if args.mirror:
        mirror_path = specs_dir(cfg) / f"{slug}.spec.md"
        mirror_action = write_if_allowed(mirror_path, normalized, force=args.force)

    payload = {
        "input": str(src),
        "slug": slug,
        "specPath": str(dest),
        "usDir": str(us_dir),
        "source": "local",
        "action": action,
        "mirror": str(mirror_path) if mirror_path else None,
        "mirrorAction": mirror_action,
    }

    if args.json:
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        print(f"slug: {slug}")
        print(f"specPath: {dest}")
        print(f"source: local")
        print(f"action: {action}")
        if mirror_path:
            print(f"mirror: {mirror_path} ({mirror_action})")

    return 0


if __name__ == "__main__":
    sys.exit(main())

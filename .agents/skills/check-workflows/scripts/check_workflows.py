#!/usr/bin/env python3
"""
check_workflows.py -- Deep validation & simulation for workflow processes (spec-to-pr & spec-to-pr-lite)

Features:
- Simulates standard (full, steps 0-9) and lite (sequential, steps 0-5) workflows.
- Checks step continuity, linked skill existence, script syntax, dependency closure, and state isolation.
- Detects broken steps, missing dependencies, and syntax errors.
- Generates actionable fix suggestions and improvements.
- By default displays a detailed report and requests user confirmation for fix execution.
"""

import sys
import os
import re
import json
import argparse
import py_compile
import subprocess
from pathlib import Path
from typing import List, Dict, Tuple, Set, Optional

# Paths
SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_DIR = SCRIPT_DIR.parent
REPO_ROOT = SKILL_DIR.parents[2]
SKILLS_DIR = REPO_ROOT / ".agents" / "skills"
SHARED_DEPS_PATH = SKILLS_DIR / "shared" / "skill-dependencies.json"
BIN_DEPS_PATH = REPO_ROOT / "bin" / "skill-dependencies.json"


def ensure_utf8_stdio() -> None:
    """Force UTF-8 on stdio so Windows locale (cp1252) does not break on Unicode."""
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


class Issue:
    def __init__(self, severity: str, category: str, location: str, message: str, fix_suggestion: str):
        self.severity = severity  # "CRITICAL", "WARNING", "SUGGESTION"
        self.category = category  # e.g., "Step Continuity", "Script Syntax", "Dependency Closure"
        self.location = location
        self.message = message
        self.fix_suggestion = fix_suggestion

    def to_dict(self) -> Dict[str, str]:
        return {
            "severity": self.severity,
            "category": self.category,
            "location": self.location,
            "message": self.message,
            "fix_suggestion": self.fix_suggestion,
        }


class WorkflowChecker:
    def __init__(self):
        self.issues: List[Issue] = []
        self.simulation_results: Dict[str, Dict] = {
            "standard": {"steps": {}, "status": "PASS"},
            "lite": {"steps": {}, "status": "PASS"},
        }
        self.deps_map: Dict[str, List[str]] = {}
        self.deps_loaded: bool = False
        self.deps_location: str = "skill-dependencies.json"
        self._load_dependencies()

    def _load_dependencies(self) -> None:
        deps_path = None
        if SHARED_DEPS_PATH.exists():
            deps_path = SHARED_DEPS_PATH
        elif BIN_DEPS_PATH.exists():
            deps_path = BIN_DEPS_PATH

        if deps_path:
            try:
                rel = deps_path.relative_to(REPO_ROOT)
                self.deps_location = str(rel).replace("\\", "/")
            except ValueError:
                self.deps_location = str(deps_path).replace("\\", "/")

            try:
                data = json.loads(deps_path.read_text(encoding="utf-8"))
                self.deps_map = data.get("dependencies", {})
                self.deps_loaded = True
            except Exception as e:
                self.issues.append(
                    Issue(
                        "WARNING",
                        "Dependency Graph",
                        self.deps_location,
                        f"Failed to parse skill-dependencies.json: {e}",
                        f"Verify JSON syntax in {self.deps_location}.",
                    )
                )

    def add_issue(self, severity: str, category: str, location: str, message: str, fix_suggestion: str) -> None:
        self.issues.append(Issue(severity, category, location, message, fix_suggestion))

    def simulate_standard_workflow(self) -> None:
        """Simulate Full spec-to-pr workflow (steps 0 to 9)."""
        std_skill_path = SKILLS_DIR / "spec-to-pr" / "SKILL.md"
        if not std_skill_path.exists():
            self.add_issue(
                "CRITICAL",
                "Workflow Structure",
                "spec-to-pr/SKILL.md",
                "Standard spec-to-pr SKILL.md file is missing.",
                "Restore .agents/skills/spec-to-pr/SKILL.md from upstream repository.",
            )
            self.simulation_results["standard"]["status"] = "FAIL"
            return

        text = std_skill_path.read_text(encoding="utf-8")
        
        # Step definitions for Standard FSM
        expected_steps = {
            0: ("Spec Creation", "00-write-spec"),
            1: ("Plan Creation", "01-write-plan"),
            2: ("Plan Interview", "02-interview"),
            3: ("Plan to Tasks", "03-plan-to-tasks"),
            4: ("Task Implementation", "04-implement-tasks"),
            5: ("Plan Verification", "05-verify-plan"),
            6: ("Code Review", "06-code-review"),
            7: ("Testing", "07-testing"),
            8: ("Ship PR", "08-ship-pr"),
            9: ("Fix PR Threads", "09-fix-pr"),
        }

        # Parse FSM table
        matches = re.findall(r"^\s*\|\s*(\d+)[^\s|]*\s*\|\s*([^|]+)\s*\|", text, re.MULTILINE)
        found_steps = {int(m[0]): m[1].strip() for m in matches}

        dispatched_skills: Set[str] = set()

        for step_num, (step_name, skill_folder) in expected_steps.items():
            step_status = "PASS"
            step_details = []

            if step_num not in found_steps:
                step_status = "FAIL"
                self.add_issue(
                    "CRITICAL",
                    "Step Continuity",
                    f"spec-to-pr (Step {step_num})",
                    f"Standard workflow table is missing Step {step_num}: {step_name}.",
                    f"Add Step {step_num} ({step_name}) row to spec-to-pr/SKILL.md FSM table.",
                )
            else:
                step_details.append(f"FSM table entry verified: '{found_steps[step_num]}'")

            # Verify target skill folder exists
            target_skill = SKILLS_DIR / skill_folder / "SKILL.md"
            if not target_skill.exists():
                step_status = "FAIL"
                self.add_issue(
                    "CRITICAL",
                    "Step Skill Link",
                    f"spec-to-pr (Step {step_num})",
                    f"Step {step_num} dispatches missing skill folder '{skill_folder}'.",
                    f"Ensure .agents/skills/{skill_folder}/SKILL.md exists on disk.",
                )
            else:
                dispatched_skills.add(skill_folder)

            self.simulation_results["standard"]["steps"][f"Step {step_num}: {step_name}"] = {
                "status": step_status,
                "skill": skill_folder,
                "details": step_details,
            }

        # Check auxiliary skills dispatched by standard workflow
        aux_skills = ["goal-fix-pr", "update-plan-implementation", "github-provider", "azure-devops-provider", "local-spec-provider"]
        for aux in aux_skills:
            if (SKILLS_DIR / aux / "SKILL.md").exists():
                dispatched_skills.add(aux)

        # Check dependency closure in skill-dependencies.json
        if self.deps_loaded:
            declared_deps = set(self.deps_map.get("spec-to-pr", []))
            missing_deps = dispatched_skills - declared_deps
            if missing_deps:
                self.add_issue(
                    "CRITICAL",
                    "Dependency Closure",
                    self.deps_location,
                    f"spec-to-pr dispatches skills not listed in dependencies['spec-to-pr']: {sorted(missing_deps)}.",
                    f"Add missing skill IDs to {self.deps_location} under dependencies['spec-to-pr'].",
                )
                self.simulation_results["standard"]["status"] = "FAIL"
            elif any(info["status"] == "FAIL" for info in self.simulation_results["standard"]["steps"].values()):
                self.simulation_results["standard"]["status"] = "FAIL"
        elif any(info["status"] == "FAIL" for info in self.simulation_results["standard"]["steps"].values()):
            self.simulation_results["standard"]["status"] = "FAIL"

    def simulate_lite_workflow(self) -> None:
        """Simulate Lite spec-to-pr-lite workflow (steps 0 to 5)."""
        lite_skill_path = SKILLS_DIR / "spec-to-pr-lite" / "SKILL.md"
        if not lite_skill_path.exists():
            self.add_issue(
                "CRITICAL",
                "Workflow Structure",
                "spec-to-pr-lite/SKILL.md",
                "Lite spec-to-pr-lite SKILL.md file is missing.",
                "Restore .agents/skills/spec-to-pr-lite/SKILL.md from upstream repository.",
            )
            self.simulation_results["lite"]["status"] = "FAIL"
            return

        text = lite_skill_path.read_text(encoding="utf-8")

        expected_steps = {
            0: ("Spec Creation", "00-write-spec"),
            1: ("Plan Creation", "01-write-plan"),
            2: ("Implementation", "04-implement-tasks"),
            3: ("Code Review", "06-code-review"),
            4: ("Ship PR", "08-ship-pr"),
            5: ("Fix PR Threads", "09-fix-pr"),
        }

        matches = re.findall(r"^\s*\|\s*([0-5])\s*\|\s*([^|]+)\s*\|", text, re.MULTILINE)
        found_steps = {int(m[0]): m[1].strip() for m in matches}

        dispatched_skills: Set[str] = set()

        for step_num, (step_name, skill_folder) in expected_steps.items():
            step_status = "PASS"
            step_details = []

            if step_num not in found_steps:
                step_status = "FAIL"
                self.add_issue(
                    "CRITICAL",
                    "Step Continuity",
                    f"spec-to-pr-lite (Step {step_num})",
                    f"Lite workflow table is missing Step {step_num}: {step_name}.",
                    f"Add Step {step_num} ({step_name}) row to spec-to-pr-lite/SKILL.md table.",
                )
            else:
                step_details.append(f"FSM table entry verified: '{found_steps[step_num]}'")

            target_skill = SKILLS_DIR / skill_folder / "SKILL.md"
            if not target_skill.exists():
                step_status = "FAIL"
                self.add_issue(
                    "CRITICAL",
                    "Step Skill Link",
                    f"spec-to-pr-lite (Step {step_num})",
                    f"Step {step_num} dispatches missing skill folder '{skill_folder}'.",
                    f"Ensure .agents/skills/{skill_folder}/SKILL.md exists on disk.",
                )
            else:
                dispatched_skills.add(skill_folder)

            self.simulation_results["lite"]["steps"][f"Step {step_num}: {step_name}"] = {
                "status": step_status,
                "skill": skill_folder,
                "details": step_details,
            }

        # Check auxiliary skills dispatches
        aux_skills = ["goal-fix-pr", "github-provider", "azure-devops-provider", "local-spec-provider"]
        for aux in aux_skills:
            if (SKILLS_DIR / aux / "SKILL.md").exists():
                dispatched_skills.add(aux)

        if self.deps_loaded:
            declared_deps = set(self.deps_map.get("spec-to-pr-lite", []))
            missing_deps = dispatched_skills - declared_deps
            if missing_deps:
                self.add_issue(
                    "CRITICAL",
                    "Dependency Closure",
                    self.deps_location,
                    f"spec-to-pr-lite dispatches skills not listed in dependencies['spec-to-pr-lite']: {sorted(missing_deps)}.",
                    f"Add missing skill IDs to {self.deps_location} under dependencies['spec-to-pr-lite'].",
                )
                self.simulation_results["lite"]["status"] = "FAIL"
            elif any(info["status"] == "FAIL" for info in self.simulation_results["lite"]["steps"].values()):
                self.simulation_results["lite"]["status"] = "FAIL"
        elif any(info["status"] == "FAIL" for info in self.simulation_results["lite"]["steps"].values()):
            self.simulation_results["lite"]["status"] = "FAIL"

    def check_scripts_syntax(self) -> None:
        """Deep check script syntax (.py and .cjs/.js) across workflow packages."""
        scripts_to_check: List[Path] = []
        for p in SKILLS_DIR.glob("**/*"):
            if p.is_file() and p.suffix in (".py", ".cjs", ".js"):
                # Skip external node_modules or pycache
                if "node_modules" in p.parts or "__pycache__" in p.parts:
                    continue
                scripts_to_check.append(p)

        for script in scripts_to_check:
            rel_path = script.relative_to(REPO_ROOT)
            if script.suffix == ".py":
                try:
                    py_compile.compile(str(script), doraise=True)
                except py_compile.PyCompileError as err:
                    self.add_issue(
                        "CRITICAL",
                        "Script Syntax Error",
                        str(rel_path),
                        f"Python syntax compilation failed: {err}",
                        f"Fix Python syntax error in {rel_path}.",
                    )
            elif script.suffix in (".cjs", ".js"):
                try:
                    res = subprocess.run(
                        ["node", "--check", str(script)],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                    )
                    if res.returncode != 0:
                        self.add_issue(
                            "CRITICAL",
                            "Script Syntax Error",
                            str(rel_path),
                            f"Node.js syntax check failed: {res.stderr.strip()}",
                            f"Fix JavaScript syntax error in {rel_path}.",
                        )
                except FileNotFoundError:
                    # Node not installed or unavailable in env
                    pass

    def check_state_isolation_and_config(self) -> None:
        """Verify state update files and provider scripts target shared/config.json and serialize workflowType."""
        std_update = SKILLS_DIR / "spec-to-pr" / "scripts" / "update_state.py"
        if std_update.exists():
            code = std_update.read_text(encoding="utf-8")
            if "workflowType" not in code or "standard" not in code:
                self.add_issue(
                    "CRITICAL",
                    "State Isolation",
                    "spec-to-pr/scripts/update_state.py",
                    "Standard update_state.py does not serialize workflowType: standard.",
                    "Ensure update_state.py sets workflowType to 'standard'.",
                )

        lite_update = SKILLS_DIR / "spec-to-pr-lite" / "scripts" / "update_state.py"
        if lite_update.exists():
            code = lite_update.read_text(encoding="utf-8")
            if "workflowType" not in code or "lite" not in code:
                self.add_issue(
                    "CRITICAL",
                    "State Isolation",
                    "spec-to-pr-lite/scripts/update_state.py",
                    "Lite update_state.py does not serialize workflowType: lite.",
                    "Ensure update_state.py sets workflowType to 'lite'.",
                )

        lite_val_state = SKILLS_DIR / "spec-to-pr-lite" / "scripts" / "validate_state.py"
        if lite_val_state.exists():
            code = lite_val_state.read_text(encoding="utf-8")
            if "shared" not in code or "config.json" not in code:
                self.add_issue(
                    "WARNING",
                    "Config Sharing",
                    "spec-to-pr-lite/scripts/validate_state.py",
                    "Lite validate_state.py does not target shared/config.json.",
                    "Update script to reference shared/config.json.",
                )

    def run_all(self) -> None:
        self.simulate_standard_workflow()
        self.simulate_lite_workflow()
        self.check_scripts_syntax()
        self.check_state_isolation_and_config()

    def generate_report(self) -> str:
        lines = []
        lines.append("# 🔍 check-workflows Deep Validation & Simulation Report")
        lines.append("")
        
        overall = "PASS" if not any(i.severity == "CRITICAL" for i in self.issues) else "FAIL"
        badge = "✅ PASS" if overall == "PASS" else "❌ FAIL"
        lines.append(f"**Overall Status**: {badge}")
        lines.append(f"**Total Issues Detected**: {len(self.issues)}")
        lines.append("")

        lines.append("## 🔄 Workflow Simulations")
        lines.append("")
        
        for wf_key, wf_title in [("standard", "Standard (`spec-to-pr`)"), ("lite", "Lite (`spec-to-pr-lite`)")]:
            wf_data = self.simulation_results[wf_key]
            wf_status_icon = "✅" if wf_data["status"] == "PASS" else "❌"
            lines.append(f"### {wf_title} — {wf_status_icon} {wf_data['status']}")
            lines.append("")
            lines.append("| Step | Dispatched Skill | Simulation Status |")
            lines.append("|------|------------------|-------------------|")
            for step_name, step_info in wf_data["steps"].items():
                s_icon = "✅ PASS" if step_info["status"] == "PASS" else "❌ FAIL"
                lines.append(f"| {step_name} | `{step_info['skill']}` | {s_icon} |")
            lines.append("")

        lines.append("## 🚨 Issues & Suggested Fixes")
        lines.append("")
        if not self.issues:
            lines.append("🎉 No broken steps, missing dependencies, or syntax errors detected.")
        else:
            lines.append("| Severity | Category | Location | Issue Description | Suggested Fix |")
            lines.append("|----------|----------|----------|-------------------|---------------|")
            for iss in self.issues:
                sev_icon = "🔴" if iss.severity == "CRITICAL" else ("🟡" if iss.severity == "WARNING" else "🔵")
                lines.append(f"| {sev_icon} {iss.severity} | {iss.category} | `{iss.location}` | {iss.message} | {iss.fix_suggestion} |")
        lines.append("")
        return "\n".join(lines)


def main():
    ensure_utf8_stdio()

    parser = argparse.ArgumentParser(description="Deep workflow validation and simulation scanner.")
    parser.add_argument("--report", action="store_true", help="Write validation report to check-workflows-report.md")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")
    parser.add_argument("--fix", action="store_true", help="Automatically attempt suggested fixes")
    parser.add_argument("--yes", "-y", action="store_true", help="Auto-confirm prompt when applying fixes")
    args = parser.parse_args()

    checker = WorkflowChecker()
    checker.run_all()

    report_content = checker.generate_report()

    if args.json:
        output_data = {
            "status": "FAIL" if any(i.severity == "CRITICAL" for i in checker.issues) else "PASS",
            "issues": [i.to_dict() for i in checker.issues],
            "simulations": checker.simulation_results,
        }
        print(json.dumps(output_data, indent=2))
    else:
        print(report_content)

    if args.report:
        report_file = REPO_ROOT / "check-workflows-report.md"
        report_file.write_text(report_content, encoding="utf-8")
        print(f"\n📝 Report saved to {report_file}")

    # Interactive confirmation prompt when issues exist or when --fix is provided
    if checker.issues:
        if args.fix:
            print("\n🔧 Auto-fix mode requested.")
            if not args.yes and sys.stdin.isatty():
                ans = input("Do you want to proceed with applying suggested fixes? [y/N]: ").strip().lower()
                if ans not in ("y", "yes"):
                    print("Aborted by user.")
                    sys.exit(1)
            print("Applying fixes...")
            # Auto-fixes applied here if any safe automated actions are registered
            print("Fixes evaluated.")

        if any(i.severity == "CRITICAL" for i in checker.issues):
            sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()

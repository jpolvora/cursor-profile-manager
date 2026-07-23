---
name: check-workflows
description: Deeply validate and simulate workflow processes (spec-to-pr & spec-to-pr-lite) near real usage. Detects broken steps, missing dependencies, script syntax errors, and suggests actionable fixes with interactive user confirmation.
upstream: jpolvora/workflow-skills — this skill is a harness validation skill. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 1.1
disable-model-invocation: true
---

# check-workflows

Deep validation and simulation skill designed to analyze, simulate, and verify the structural integrity of both the standard `spec-to-pr` (steps 0–9) and sequential `spec-to-pr-lite` (steps 0–5) workflow orchestrators.

---

## Quick Start

Run deep simulation and validation against both workflows:

```bash
# Standard report execution
python .agents/skills/check-workflows/scripts/check_workflows.py

# Save Markdown report to check-workflows-report.md
python .agents/skills/check-workflows/scripts/check_workflows.py --report

# Interactive auto-fix mode (prompts for confirmation before applying)
python .agents/skills/check-workflows/scripts/check_workflows.py --fix

# Non-interactive auto-fix (CI / automated runner)
python .agents/skills/check-workflows/scripts/check_workflows.py --fix --yes
```

---

## Simulation & Validation Scope

The validation process performs end-to-end simulation across both orchestrators:

### 1. Workflow Simulation & Step Continuity
- **Standard (`spec-to-pr`) Simulation**: Simulates stepping through Steps 0 to 9 (`00-write-spec`, `01-write-plan`, `02-interview`, `03-plan-to-tasks`, `04-implement-tasks`, `05-verify-plan`, `06-code-review`, `07-testing`, `08-ship-pr`, `09-fix-pr`).
- **Lite (`spec-to-pr-lite`) Simulation**: Simulates stepping through Steps 0 to 5 (`00-write-spec`, `01-write-plan`, `04-implement-tasks`, `06-code-review`, `08-ship-pr`, `09-fix-pr`).
- **Linked Skill Check**: Verifies that every step links to an existing skill under `.agents/skills/<skill>/SKILL.md`.

### 2. Script Syntax & Execution Check
- Compiles Python scripts (`.py`) via `py_compile` and checks Node.js scripts (`.cjs`/`.js`) via `node --check`.
- Flags syntax errors, invalid imports, or execution issues as critical broken steps.

### 3. Orchestrator Dependency Closure
- Asserts that all skills dispatched by `spec-to-pr` and `spec-to-pr-lite` are declared in `bin/skill-dependencies.json`.

### 4. Config Sharing & State Isolation
- Verifies that all provider scripts and state handlers target `shared/config.json`.
- Confirms state handlers serialize `workflowType` (`standard` vs `lite`).

---

## Report & Confirmation Flow

1. **Detailed Simulation Report**: Generates a structured breakdown of Full and Lite workflow simulation results, along with a table of detected issues and actionable **Suggested Fixes**.
2. **User Confirmation Gate**: Prompts for explicit user confirmation before applying automated fixes.

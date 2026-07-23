# State Hygiene Protocol

After step N, before the progress board, the orchestrator MUST execute State Hygiene.

**Applies in `autoMode` / `fullMode` / `dryRun` the same as normal.** Skipping hygiene or omitting `--elapsed` → **HS-5**.

## Automated update

```bash
python .agents/skills/spec-to-pr/scripts/update_state.py \
  {plansDir}/{slug}/{workflow-id}.state.md \
  --step {N} \
  --status {completed|failed|skipped} \
  --elapsed {elapsedSec} \
  --tokens {promptTokens}:{completionTokens} \
  --model {modelName} \
  --created "{comma_separated_created_files}" \
  --modified "{comma_separated_modified_files}" \
  --deleted "{comma_separated_deleted_files}" \
  --gate-choice "{gateChoice}"
```

### `--elapsed` (mandatory)

| Status | Rule |
|--------|------|
| `completed` / `failed` | `--elapsed` **required** (integer ≥ 0). Measure agent wall-clock for the step (dispatch → step-output). **Do not omit** (script rejects missing flag). **Do not invent 0** unless the step truly finished in under 1s. |
| `skipped` | `--elapsed 0` allowed (script defaults to 0 when status is skipped). |

Source: `step-output.telemetry.elapsedSec`. Missing telemetry on a completed/failed step → **HS-5** before Progress Board.

Script also:

- Writes `telemetry.steps[]` + recomputes `totalElapsedSec` / `totalTokens` (null `elapsedSec` treated as 0)
- Upserts `## Telemetry log` table row in the state body
- Appends `## Gate history` line

## Manual fallback (if Python unavailable)

```yaml
- Refresh currentModel from executing session model (unknown if unavailable). If changed vs prior, log model-change | step {N} | {old} → {new} | ISO in ## Gate history. Ignore leftover modelChain.
- Pass session model into --model {modelName} when calling update_state.py (recorder only; not a user override flag)
- Append ## Step outputs ### Step N (include model: {modelName} in block)
- Append step-output.learning → ## Workflow memory (dedupe)
- Merge files_touched → ## Step file log ### Step N
- Append to ## Step model log: | Step N | {label} | {model} | dispatched {ISO} |
- Record telemetry: elapsedSec, promptTokens, completionTokens, estimated → ## Telemetry ### Step N
- Append to ## Telemetry log: | Step N | {label} | {model} | {elapsedSec}s | {tokens} |
- Recompute workflowManifest; update completedSteps, stepStatus, currentStep
- Assert created paths exist; currentStep = next gate
- Step 2: ## Refinement registry
```

Fail hygiene → **HS-5** (STOP before Progress Board).

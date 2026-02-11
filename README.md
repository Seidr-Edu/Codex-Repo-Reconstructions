# Andvari

Andvari runs a local diagram-to-Java reconstruction pipeline using Codex CLI.

Input: PlantUML (`.puml`)  
Output: isolated reconstructed repository, gate logs, and run report

## Single command

```bash
./andvari-run.sh --diagram /path/to/diagram.puml --run-id optional-id --max-iter 8
```

- `--diagram` is required.
- `--run-id` is optional. If omitted, a UTC timestamp id is generated.
- `--max-iter` is optional. It controls automatic repair loops after the initial generation.

## What the runner does

1. Creates a fresh workspace:
   - `runs/<run_id>/input`
   - `runs/<run_id>/new_repo`
   - `runs/<run_id>/logs`
   - `runs/<run_id>/outputs`
2. Copies the input diagram to `runs/<run_id>/input/diagram.puml`.
3. Copies `AGENTS.md` and `gate_recon.sh` to `runs/<run_id>/new_repo`.
4. Runs `codex exec` from `runs/<run_id>/new_repo` with reconstruction instructions.
5. Runs `./gate_recon.sh` locally.
6. If gate fails, loops:
   - summarize latest gate failure (`tail -n 200`)
   - call `codex exec` with fix instructions + summary
   - rerun gate
   - stop on pass or after `--max-iter`
7. Writes artifacts and run report.

The gate enforces:
- no stub markers
- exactly one build system (Gradle or Maven)
- tests passing
- at least one production `main` entrypoint
- executable `./run_demo.sh` and successful demo smoke run

## Artifacts

Per run:

- `runs/<run_id>/logs/codex_events.jsonl`
- `runs/<run_id>/logs/codex_stderr.log`
- `runs/<run_id>/logs/gate.log`
- `runs/<run_id>/outputs/run_report.md`

## Prerequisites

- `codex` CLI installed and on `PATH`
- active Codex auth (`codex login status` must succeed)
- Bash
- Java + build tooling required by the generated project
- `rg` (used by `gate_recon.sh`)

The runner fails fast with actionable errors if Codex CLI is missing, unauthenticated, or cannot write its local session directory.

## Adapter design

The runner uses an adapter entrypoint:

- `scripts/adapters/adapter.sh`
- `scripts/adapters/codex.sh`

Only the Codex adapter is implemented now, but the orchestration is structured so other model adapters can be added later without rewriting `andvari-run.sh`.

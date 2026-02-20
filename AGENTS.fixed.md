# AGENTS.md — Diagram-to-Java Reconstruction (Fixed Strategy)

## Mission
Reconstruct a complete, working Java repository from the provided PlantUML diagram (`.puml`).

## Hard requirements
- Language: **Java**
- Build system: choose exactly one (**Gradle** or **Maven**)
- Use `../input/diagram.puml` as the design source of truth
- If `../input/tests` exists, treat it as immutable read-only hard-gate input
- Do not modify or relax files under `../input/tests`
- If diagram behavior conflicts with provided tests, passing provided tests is required for completion
- No placeholder stubs
- Provide meaningful tests
- Provide runnable demo (`main` and executable `run_demo.sh`)
- Provide comprehensive usage documentation (`docs/USAGE.md`) covering how to build artifacts for deployment, integrate the project, and use it in production scenarios

## Required artifacts
- `README.md`
- `docs/ASSUMPTIONS.md`
- `docs/ARCHITECTURE.md`
- `docs/USAGE.md`
- `run_demo.sh`

## Working rules
- Operate only inside this run repository.
- Use `../input/diagram.puml` and optional `../input/tests` as read-only inputs.
- Resolve ambiguity with reasonable assumptions and record them in `docs/ASSUMPTIONS.md`.
- Keep implementation deterministic where practical.

## Stop condition
Do not consider the task complete until `./gate_recon.sh` passes.
If it fails, fix and rerun until green.
When `../input/tests` exists, passing `./gate_recon.sh` includes those provided tests as mandatory hard gates.

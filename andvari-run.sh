#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAPTER_LIB="${ROOT_DIR}/scripts/adapters/adapter.sh"

usage() {
  cat <<'EOF'
Usage:
  ./andvari-run.sh --diagram /path/to/diagram.puml [--run-id RUN_ID] [--max-iter N]

Options:
  --diagram   Path to the PlantUML diagram (.puml). Required.
  --run-id    Optional run id. Auto-generated (UTC timestamp) if omitted.
  --max-iter  Maximum gate-repair iterations after initial reconstruction. Default: 8.
  -h, --help  Show this help.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

validate_run_id() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]]
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "File not found: $path"
}

if [[ ! -f "$ADAPTER_LIB" ]]; then
  fail "Missing adapter library: $ADAPTER_LIB"
fi

# shellcheck source=/dev/null
source "$ADAPTER_LIB"

DIAGRAM_PATH=""
RUN_ID=""
MAX_ITER="8"
ADAPTER="${ANDVARI_ADAPTER:-codex}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --diagram)
      [[ $# -ge 2 ]] || fail "--diagram requires a value"
      DIAGRAM_PATH="$2"
      shift 2
      ;;
    --run-id)
      [[ $# -ge 2 ]] || fail "--run-id requires a value"
      RUN_ID="$2"
      shift 2
      ;;
    --max-iter)
      [[ $# -ge 2 ]] || fail "--max-iter requires a value"
      MAX_ITER="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$DIAGRAM_PATH" ]] || fail "--diagram is required"
require_file "$DIAGRAM_PATH"

if [[ -z "$RUN_ID" ]]; then
  RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")"
fi

validate_run_id "$RUN_ID" || fail "Invalid --run-id '$RUN_ID' (allowed: letters, numbers, ., _, -)"
[[ "$MAX_ITER" =~ ^[0-9]+$ ]] || fail "--max-iter must be a non-negative integer"
# Force decimal interpretation so values like 08 do not trigger bash octal parsing errors.
MAX_ITER=$((10#$MAX_ITER))

RUNS_DIR="${ROOT_DIR}/runs"
RUN_DIR="${RUNS_DIR}/${RUN_ID}"
INPUT_DIR="${RUN_DIR}/input"
NEW_REPO_DIR="${RUN_DIR}/new_repo"
LOGS_DIR="${RUN_DIR}/logs"
OUTPUTS_DIR="${RUN_DIR}/outputs"

if [[ -e "$RUN_DIR" ]]; then
  fail "Run directory already exists: $RUN_DIR. Use a different --run-id."
fi

require_file "${ROOT_DIR}/AGENTS.md"
require_file "${ROOT_DIR}/gate_recon.sh"
adapter_check_prereqs "$ADAPTER"

mkdir -p "$INPUT_DIR" "$NEW_REPO_DIR" "$LOGS_DIR" "$OUTPUTS_DIR"
cp "$DIAGRAM_PATH" "${INPUT_DIR}/diagram.puml"
cp "${ROOT_DIR}/AGENTS.md" "${NEW_REPO_DIR}/AGENTS.md"
cp "${ROOT_DIR}/gate_recon.sh" "${NEW_REPO_DIR}/gate_recon.sh"
chmod +x "${NEW_REPO_DIR}/gate_recon.sh"

EVENTS_LOG="${LOGS_DIR}/codex_events.jsonl"
CODEX_STDERR_LOG="${LOGS_DIR}/codex_stderr.log"
GATE_LOG="${LOGS_DIR}/gate.log"
LAST_GATE_OUTPUT="${LOGS_DIR}/gate_last.log"
GATE_SUMMARY_FILE="${LOGS_DIR}/gate_summary.txt"
RUN_REPORT="${OUTPUTS_DIR}/run_report.md"

touch "$EVENTS_LOG" "$CODEX_STDERR_LOG" "$GATE_LOG"

START_TIME="$(timestamp_utc)"
START_EPOCH="$(date -u +%s)"
STATUS="failed"
REPAIR_ITERATIONS_USED=0
ADAPTER_FAILURES=0

run_gate() {
  local label="$1"
  local run_time
  run_time="$(timestamp_utc)"

  echo "=== ${label} @ ${run_time} ===" >> "$GATE_LOG"

  set +e
  (
    cd "$NEW_REPO_DIR"
    ./gate_recon.sh
  ) > "$LAST_GATE_OUTPUT" 2>&1
  local gate_status=$?
  set -e

  cat "$LAST_GATE_OUTPUT" | tee -a "$GATE_LOG"
  echo >> "$GATE_LOG"

  return "$gate_status"
}

summarize_last_gate_failure() {
  tail -n 200 "$LAST_GATE_OUTPUT" > "$GATE_SUMMARY_FILE"
}

echo "[andvari] run id: ${RUN_ID}"
echo "[andvari] run dir: ${RUN_DIR}"
echo "[andvari] adapter: ${ADAPTER}"
echo "[andvari] starting initial reconstruction..."

if ! adapter_run_initial_reconstruction \
  "$ADAPTER" \
  "$NEW_REPO_DIR" \
  "${INPUT_DIR}/diagram.puml" \
  "$EVENTS_LOG" \
  "$CODEX_STDERR_LOG" \
  "${OUTPUTS_DIR}/codex_last_message_initial.txt"; then
  ADAPTER_FAILURES=$((ADAPTER_FAILURES + 1))
  echo "[andvari] warning: initial adapter run returned non-zero status"
fi

if run_gate "gate-initial"; then
  STATUS="passed"
else
  for ((iter = 1; iter <= MAX_ITER; iter++)); do
    REPAIR_ITERATIONS_USED="$iter"
    summarize_last_gate_failure
    echo "[andvari] gate failed, running repair iteration ${iter}/${MAX_ITER}..."

    if ! adapter_run_fix_iteration \
      "$ADAPTER" \
      "$NEW_REPO_DIR" \
      "${INPUT_DIR}/diagram.puml" \
      "$GATE_SUMMARY_FILE" \
      "$EVENTS_LOG" \
      "$CODEX_STDERR_LOG" \
      "${OUTPUTS_DIR}/codex_last_message_iter_${iter}.txt" \
      "$iter"; then
      ADAPTER_FAILURES=$((ADAPTER_FAILURES + 1))
      echo "[andvari] warning: adapter repair iteration ${iter} returned non-zero status"
    fi

    if run_gate "gate-retry-${iter}"; then
      STATUS="passed"
      break
    fi
  done
fi

END_TIME="$(timestamp_utc)"
END_EPOCH="$(date -u +%s)"
DURATION_SECONDS=$((END_EPOCH - START_EPOCH))

cat > "$RUN_REPORT" <<EOF
# Run Report

- Run ID: \`${RUN_ID}\`
- Adapter: \`${ADAPTER}\`
- Diagram: \`runs/${RUN_ID}/input/diagram.puml\`
- Status: \`${STATUS}\`
- Max Repair Iterations: \`${MAX_ITER}\`
- Repair Iterations Used: \`${REPAIR_ITERATIONS_USED}\`
- Adapter Non-zero Runs: \`${ADAPTER_FAILURES}\`
- Started (UTC): \`${START_TIME}\`
- Finished (UTC): \`${END_TIME}\`
- Duration (seconds): \`${DURATION_SECONDS}\`

## Artifacts

- Codex events log: \`runs/${RUN_ID}/logs/codex_events.jsonl\`
- Codex stderr log: \`runs/${RUN_ID}/logs/codex_stderr.log\`
- Gate log: \`runs/${RUN_ID}/logs/gate.log\`
- Report: \`runs/${RUN_ID}/outputs/run_report.md\`
EOF

if [[ "$STATUS" == "passed" ]]; then
  echo "[andvari] status: PASS"
  echo "[andvari] run folder: ${RUN_DIR}"
  exit 0
fi

echo "[andvari] status: FAIL"
echo "[andvari] run folder: ${RUN_DIR}"
echo "[andvari] see logs: ${GATE_LOG}, ${CODEX_STDERR_LOG}, ${EVENTS_LOG}"
exit 1

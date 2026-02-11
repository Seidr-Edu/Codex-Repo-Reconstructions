#!/usr/bin/env bash
set -euo pipefail

timestamp_utc_adapter() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

append_adapter_event() {
  local events_log="$1"
  local phase="$2"
  local iteration="$3"
  local run_time
  run_time="$(timestamp_utc_adapter)"

  printf '{"type":"andvari.adapter","adapter":"codex","phase":"%s","iteration":"%s","time":"%s"}\n' \
    "$phase" "$iteration" "$run_time" >> "$events_log"
}

codex_check_prereqs() {
  if ! command -v codex >/dev/null 2>&1; then
    echo "codex CLI not found. Install Codex CLI and ensure 'codex' is on PATH." >&2
    return 1
  fi

  local codex_home="${CODEX_HOME:-${HOME}/.codex}"
  local session_dir="${codex_home}/sessions"
  if [[ -e "$codex_home" && ! -w "$codex_home" ]]; then
    cat >&2 <<EOF
codex CLI home is not writable: ${codex_home}
Fix ownership/permissions, for example:
  sudo chown -R \$(whoami) "${codex_home}"
EOF
    return 1
  fi
  if [[ -e "$session_dir" && ! -w "$session_dir" ]]; then
    cat >&2 <<EOF
codex CLI session directory is not writable: ${session_dir}
Fix ownership/permissions, for example:
  sudo chown -R \$(whoami) "${codex_home}"
EOF
    return 1
  fi

  if ! codex login status >/dev/null 2>&1; then
    cat >&2 <<'EOF'
codex CLI is not authenticated.
Run one of:
  codex login
  printenv OPENAI_API_KEY | codex login --with-api-key
EOF
    return 1
  fi
}

run_codex_prompt() {
  local new_repo_dir="$1"
  local input_diagram_path="$2"
  local prompt_file="$3"
  local events_log="$4"
  local stderr_log="$5"
  local output_last_message="$6"

  local input_dir
  input_dir="$(cd "$(dirname "$input_diagram_path")" && pwd)"

  set +e
  (
    cd "$new_repo_dir"
    codex exec \
      --skip-git-repo-check \
      --full-auto \
      --add-dir "$input_dir" \
      --json \
      --output-last-message "$output_last_message" \
      - < "$prompt_file"
  ) >> "$events_log" 2>> "$stderr_log"
  local status=$?
  set -e

  return "$status"
}

codex_run_initial_reconstruction() {
  local new_repo_dir="$1"
  local input_diagram_path="$2"
  local events_log="$3"
  local stderr_log="$4"
  local output_last_message="$5"

  local prompt_file
  prompt_file="$(mktemp)"

  cat > "$prompt_file" <<'EOF'
Reconstruct this Java repository from the source-of-truth diagram at:
../input/diagram.puml

Policy:
- Follow AGENTS.md in this repository as the authoritative requirements document.
- If any instruction in this prompt appears to conflict with AGENTS.md, AGENTS.md wins.

Execution:
1. Read ../input/diagram.puml.
2. Reconstruct the repo accordingly.
3. Run ./gate_recon.sh.
4. If gate fails, fix and rerun until it passes.

Scope constraints:
- Operate only inside this run repository.
- Use ../input/diagram.puml as read-only input.
- Do not inspect or modify any other run directories.

Return a concise summary including final gate result.
EOF

  append_adapter_event "$events_log" "initial" "0"
  local status
  set +e
  run_codex_prompt \
    "$new_repo_dir" \
    "$input_diagram_path" \
    "$prompt_file" \
    "$events_log" \
    "$stderr_log" \
    "$output_last_message"
  status=$?
  set -e

  rm -f "$prompt_file"
  return "$status"
}

codex_run_fix_iteration() {
  local new_repo_dir="$1"
  local input_diagram_path="$2"
  local gate_summary_file="$3"
  local events_log="$4"
  local stderr_log="$5"
  local output_last_message="$6"
  local iteration="$7"

  local prompt_file
  prompt_file="$(mktemp)"

  {
    cat <<'EOF'
Gate failed. Fix the repository and get gate_recon.sh to pass.

Source diagram:
../input/diagram.puml

Policy:
- Follow AGENTS.md in this repository as the authoritative requirements document.
- If any instruction in this prompt appears to conflict with AGENTS.md, AGENTS.md wins.

Actions:
1. Read the gate failure summary below.
2. Apply fixes in this repository.
3. Run ./gate_recon.sh.
4. If gate still fails, continue fixing and rerunning until it passes.
5. Return concise summary of root cause and fixes.

Gate failure summary (last ~200 lines):
EOF
    echo "----- BEGIN GATE SUMMARY -----"
    cat "$gate_summary_file"
    echo "----- END GATE SUMMARY -----"
  } > "$prompt_file"

  append_adapter_event "$events_log" "repair" "$iteration"
  local status
  set +e
  run_codex_prompt \
    "$new_repo_dir" \
    "$input_diagram_path" \
    "$prompt_file" \
    "$events_log" \
    "$stderr_log" \
    "$output_last_message"
  status=$?
  set -e

  rm -f "$prompt_file"
  return "$status"
}

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "== gate_hard: starting =="
echo "Repo: $ROOT"

fail() {
  echo "== gate_hard: FAIL =="
  echo "$1" >&2
  exit 1
}

info() {
  echo "[gate_hard] $1"
}

sync_provided_tests_if_present() {
  local provided_tests_dir="../input/tests"
  local provided_java_dir="${provided_tests_dir}/java"
  local provided_resources_dir="${provided_tests_dir}/resources"
  local java_file_count

  if [[ ! -d "$provided_tests_dir" ]]; then
    return 0
  fi

  info "Syncing provided hard tests from ${provided_tests_dir}"
  [[ -d "$provided_java_dir" ]] || fail "Provided tests pack is invalid: missing ${provided_java_dir}"

  java_file_count="$(find "$provided_java_dir" -type f -name "*.java" 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$java_file_count" -ge 1 ]] || fail "Provided tests pack is invalid: no .java files under ${provided_java_dir}"

  mkdir -p src/test/java
  cp -R "${provided_java_dir}/." src/test/java/

  if [[ -d "$provided_resources_dir" ]]; then
    mkdir -p src/test/resources
    cp -R "${provided_resources_dir}/." src/test/resources/
  fi

  info "Provided hard tests synced (${java_file_count} Java file(s))."
}

run_demo_with_optional_timeout() {
  local log_file="$1"
  if command -v timeout >/dev/null 2>&1; then
    timeout 60 ./run_demo.sh > "$log_file" 2>&1
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 60 ./run_demo.sh > "$log_file" 2>&1
  else
    ./run_demo.sh > "$log_file" 2>&1
  fi
}

# --- Required docs/artifacts ---
info "Checking required docs..."
[[ -f README.md ]] || fail "Missing README.md"
[[ -f docs/ASSUMPTIONS.md ]] || fail "Missing docs/ASSUMPTIONS.md"
[[ -f docs/ARCHITECTURE.md ]] || fail "Missing docs/ARCHITECTURE.md"
[[ -f docs/USAGE.md ]] || fail "Missing docs/USAGE.md"

info "Checking README demo instructions..."
rg -n "run_demo\\.sh" README.md >/dev/null 2>&1 || fail "README.md must document how to run ./run_demo.sh"

# --- Java project + entrypoint sanity ---
info "Checking Java source exists..."
[[ -d src/main/java ]] || fail "Missing src/main/java"
JAVA_FILE_COUNT="$(find src/main/java -type f -name "*.java" 2>/dev/null | wc -l | tr -d ' ')"
[[ "$JAVA_FILE_COUNT" -ge 1 ]] || fail "No Java files found under src/main/java"

info "Checking for production main entrypoint..."
MAIN_COUNT="$(rg -n -g "*.java" \
  "public\\s+static\\s+void\\s+main\\s*\\(\\s*(final\\s+)?String(\\[\\]|\\.\\.\\.)\\s*[A-Za-z_][A-Za-z0-9_]*\\s*\\)" \
  src/main/java 2>/dev/null | wc -l | tr -d ' ')"
[[ "$MAIN_COUNT" -ge 1 ]] || fail "No production main entrypoint found in src/main/java"
info "Found $MAIN_COUNT production main entrypoint(s)."

# --- No-stubs policy ---
info "Checking for forbidden stub markers..."
MARKER="TODO-""STUB:"
if rg -n --glob "!gate_hard.sh" --glob "!gate_recon.sh" "$MARKER" . >/dev/null 2>&1; then
  rg -n --glob "!gate_hard.sh" --glob "!gate_recon.sh" "$MARKER" . || true
  fail "Found ${MARKER} markers. Replace stubs with real implementations."
fi

if [[ -d src/main ]]; then
  info "Scanning src/main for obvious stub patterns..."
  if rg -n --glob "src/main/**" \
    -e "return null;" \
    -e "throw new UnsupportedOperationException\\(" \
    -e "throw new NotImplementedError\\(" \
    . >/dev/null 2>&1; then
    rg -n --glob "src/main/**" \
      -e "return null;" \
      -e "throw new UnsupportedOperationException\\(" \
      -e "throw new NotImplementedError\\(" \
      . || true
    fail "Found obvious stub implementations in src/main."
  fi
fi

# --- Detect build tool and run tests ---
info "Detecting build tool..."
USE_GRADLE="false"
USE_MAVEN="false"
HAS_GRADLE_FILES="false"
HAS_MAVEN_FILES="false"

if [[ -x ./gradlew ]]; then
  HAS_GRADLE_FILES="true"
elif [[ -f build.gradle || -f build.gradle.kts || -f settings.gradle || -f settings.gradle.kts ]]; then
  HAS_GRADLE_FILES="true"
fi

if [[ -f pom.xml ]]; then
  HAS_MAVEN_FILES="true"
fi

if [[ "$HAS_GRADLE_FILES" == "true" && "$HAS_MAVEN_FILES" == "true" ]]; then
  fail "Both Gradle and Maven build definitions detected. Choose exactly one build system."
fi

if [[ "$HAS_GRADLE_FILES" != "true" && "$HAS_MAVEN_FILES" != "true" ]]; then
  fail "No build system detected. Expected Gradle or Maven."
fi

if [[ "$HAS_GRADLE_FILES" == "true" ]]; then
  [[ -x ./gradlew ]] || fail "Gradle build detected but executable ./gradlew is missing."
  USE_GRADLE="true"
fi

if [[ "$HAS_MAVEN_FILES" == "true" ]]; then
  USE_MAVEN="true"
fi

sync_provided_tests_if_present

info "Checking tests exist..."
TEST_FILES_COUNT=0
if [[ -d src/test ]]; then
  TEST_FILES_COUNT="$(find src/test -type f \( -name "*Test.java" -o -name "*Tests.java" \) 2>/dev/null | wc -l | tr -d ' ')"
fi

if [[ "$TEST_FILES_COUNT" -lt 1 && -d src/test/java ]]; then
  TEST_FILES_COUNT="$(find src/test/java -type f -name "*Test.java" 2>/dev/null | wc -l | tr -d ' ')"
fi

[[ "$TEST_FILES_COUNT" -ge 1 ]] || fail "No Java test files found under src/test"
info "Found $TEST_FILES_COUNT test file(s)."

sync_provided_tests_if_present

if [[ "$USE_GRADLE" == "true" ]]; then
  info "Running: ./gradlew test"
  ./gradlew test
fi

if [[ "$USE_MAVEN" == "true" ]]; then
  command -v mvn >/dev/null 2>&1 || fail "Maven build detected but 'mvn' not found."
  info "Running: mvn -q test"
  mvn -q test
fi

# --- Runnable demo ---
info "Checking demo launcher..."
[[ -f run_demo.sh ]] || fail "Missing run_demo.sh"
[[ -x run_demo.sh ]] || fail "run_demo.sh exists but is not executable"

info "Running demo smoke command: ./run_demo.sh"
DEMO_LOG="$(mktemp)"
set +e
run_demo_with_optional_timeout "$DEMO_LOG"
DEMO_STATUS=$?
set -e

cat "$DEMO_LOG"
rm -f "$DEMO_LOG"

[[ "$DEMO_STATUS" -eq 0 ]] || fail "Demo command failed (./run_demo.sh exit code: $DEMO_STATUS)."

echo "== gate_hard: PASS =="

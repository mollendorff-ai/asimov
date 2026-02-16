#!/usr/bin/env bash
# Shared test helpers for asimov bats tests

# Project root (one level up from test/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASIMOV_BIN="${PROJECT_ROOT}/bin/asimov"

# Create an isolated temp dir for each test
setup_tmpdir() {
    TEST_TMPDIR="$(mktemp -d)"
    export HOME="${TEST_TMPDIR}/fakehome"
    mkdir -p "$HOME"
    export ASIMOV_DATA="${PROJECT_ROOT}"
}

teardown_tmpdir() {
    [ -n "${TEST_TMPDIR:-}" ] && rm -rf "$TEST_TMPDIR"
}

# Create a fake project directory and cd into it
setup_project() {
    local name="${1:-testproj}"
    PROJECT_DIR="${TEST_TMPDIR}/${name}"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
}

# Source only the functions from bin/asimov (no main execution)
# We extract functions by sourcing with a guard
source_asimov_functions() {
    # Override the case/main block by setting a flag
    export __ASIMOV_TESTING=1
    # Source functions from the script
    eval "$(sed '/^case "\${1:-}"/,$ d' "$ASIMOV_BIN")"
}

# Create a minimal config.yaml for testing
create_test_config() {
    local dir="${1:-$HOME/.asimov}"
    mkdir -p "$dir"
    cat > "${dir}/config.yaml" << 'YAML'
launch:
  default_ai: claude

  claude:
    model: opus
    args:
      - --dangerously-skip-permissions
    env:
      MAX_THINKING_TOKENS: "1000000"

  gemini:
    args:
      - --yolo
YAML
}

# Create a minimal .asimov/ project directory
create_test_asimov_dir() {
    mkdir -p .asimov
    cat > .asimov/project.yaml << 'YAML'
identity:
  name: testproj
  type: shell
YAML
    cat > .asimov/roadmap.yaml << 'YAML'
current:
  version: "1.0.0"
  status: in_progress
  summary: "Test sprint"
YAML
    for proto in freshness.json sycophancy.json sprint.json coding-standards.json; do
        cp "${PROJECT_ROOT}/protocols/${proto}" ".asimov/${proto}"
    done
}

# Mock a command (creates a stub in PATH)
mock_command() {
    local cmd="$1"
    local exit_code="${2:-0}"
    local output="${3:-}"
    local mock_dir="${TEST_TMPDIR}/mocks"
    mkdir -p "$mock_dir"
    cat > "${mock_dir}/${cmd}" << EOF
#!/bin/bash
${output:+echo "$output"}
exit $exit_code
EOF
    chmod +x "${mock_dir}/${cmd}"
    export PATH="${mock_dir}:${PATH}"
}

# Remove a command from mock PATH
unmock_command() {
    local cmd="$1"
    rm -f "${TEST_TMPDIR}/mocks/${cmd}"
}

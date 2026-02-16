#!/usr/bin/env bats

load test_helper

HOOK="${PROJECT_ROOT}/hooks/pre-commit"

setup() {
    setup_tmpdir
    setup_project "hooktest"
}

teardown() {
    teardown_tmpdir
}

# ─── Language detection ──────────────────────────────────────────────────

@test "pre-commit detects rust project via Cargo.toml" {
    touch Cargo.toml
    # Mock all rust tools to succeed
    mock_command "cargo" 0
    mock_command "cargo-llvm-cov" 0
    run "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RUST QUALITY CHECKS"* ]]
}

@test "pre-commit detects python project via pyproject.toml" {
    touch pyproject.toml
    mock_command "ruff" 0
    mock_command "pytest" 0
    # Mock python to make pytest-cov import check pass
    mock_command "python" 0
    run "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PYTHON QUALITY CHECKS"* ]]
}

@test "pre-commit detects python project via setup.py" {
    touch setup.py
    mock_command "ruff" 0
    mock_command "pytest" 0
    mock_command "python" 0
    run "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PYTHON QUALITY CHECKS"* ]]
}

@test "pre-commit detects python project via requirements.txt" {
    touch requirements.txt
    mock_command "ruff" 0
    mock_command "pytest" 0
    mock_command "python" 0
    run "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PYTHON QUALITY CHECKS"* ]]
}

@test "pre-commit detects node project via package.json" {
    echo '{}' > package.json
    mock_command "npx" 0
    mock_command "npm" 0
    run "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NODE.JS QUALITY CHECKS"* ]]
}

@test "pre-commit detects go project via go.mod" {
    touch go.mod
    mock_command "gofumpt" 0 ""
    mock_command "golangci-lint" 0
    mock_command "go" 0
    mock_command "go-test-coverage" 0
    touch .testcoverage.yml
    run "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GO QUALITY CHECKS"* ]]
}

@test "pre-commit detects flutter project via pubspec.yaml" {
    touch pubspec.yaml
    mock_command "dart" 0
    mock_command "flutter" 0
    mock_command "lcov" 0 "  lines......: 100.0% (50 of 50 lines)"
    mkdir -p coverage
    echo "" > coverage/lcov.info
    run "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FLUTTER/DART QUALITY CHECKS"* ]]
}

# ─── No project markers → passes clean ──────────────────────────────────

@test "pre-commit passes when no project markers found" {
    run "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALL QUALITY GATES PASSED"* ]]
}

# ─── Failure cases ──────────────────────────────────────────────────────

@test "pre-commit fails when rust format fails" {
    touch Cargo.toml
    mock_command "cargo" 1
    run "$HOOK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FORMAT FAILED"* ]]
}

@test "pre-commit fails when ruff not installed for python" {
    touch pyproject.toml
    # No ruff mock — unmock to ensure it's not found
    unmock_command "ruff" 2>/dev/null || true
    run "$HOOK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ruff is not installed"* ]]
}

@test "pre-commit fails when gofumpt not installed for go" {
    touch go.mod
    unmock_command "gofumpt" 2>/dev/null || true
    run "$HOOK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"gofumpt is not installed"* ]]
}

# ─── Success banner ─────────────────────────────────────────────────────

@test "pre-commit shows success banner on pass" {
    run "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALL QUALITY GATES PASSED"* ]]
}

# ─── Hook structure ─────────────────────────────────────────────────────

@test "pre-commit is executable" {
    [ -x "$HOOK" ]
}

@test "pre-commit has LLM warning header" {
    run grep -c "WARNING TO LLM AGENTS" "$HOOK"
    [ "$output" -ge 1 ]
}

@test "pre-commit has set -e" {
    run grep -c "^set -e" "$HOOK"
    [ "$output" -ge 1 ]
}

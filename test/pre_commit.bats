#!/usr/bin/env bats

load test_helper

HOOK="${PROJECT_ROOT}/hooks/pre-commit"

setup() {
    setup_tmpdir
    setup_project "hooktest"
    # Keep git from finding a repository above the test folder
    export GIT_CEILING_DIRECTORIES="$TEST_TMPDIR"
    export TMPDIR="${TEST_TMPDIR}/tmp"
    mkdir -p "$TMPDIR"
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
    # Hide any ruff installed on the host so the test does not depend on it
    unmock_command "ruff" 2>/dev/null || true
    PATH="$(path_without ruff)" run "$HOOK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ruff is not installed"* ]]
}

@test "pre-commit fails when gofumpt not installed for go" {
    touch go.mod
    unmock_command "gofumpt" 2>/dev/null || true
    PATH="$(path_without gofumpt)" run "$HOOK"
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

# ─── Python lint config ─────────────────────────────────────────────────

_mock_python_tools() {
    mock_command "ruff" 0
    mock_command "pytest" 0
    mock_command "python" 0
}

@test "pre-commit runs the python coverage gate through python -m pytest" {
    touch pyproject.toml
    mock_command "ruff" 0
    # python logs its arguments and succeeds; a bare pytest on PATH is not used
    cat > "${TEST_TMPDIR}/mocks/python" << EOF
#!/bin/bash
echo "\$*" >> "${TEST_TMPDIR}/python.log"
exit 0
EOF
    chmod +x "${TEST_TMPDIR}/mocks/python"
    mock_command "pytest" 1
    run "$HOOK"
    [ "$status" -eq 0 ]
    grep -q -- '-m pytest --cov=. --cov-fail-under=100' "${TEST_TMPDIR}/python.log"
}

@test "pre-commit fails when python has no pytest-cov even if a pytest command exists" {
    touch pyproject.toml
    mock_command "ruff" 0
    mock_command "pytest" 0
    cat > "${TEST_TMPDIR}/mocks/python" << 'EOF'
#!/bin/bash
case "$*" in *pytest_cov*) exit 1 ;; esac
exit 0
EOF
    chmod +x "${TEST_TMPDIR}/mocks/python"
    run "$HOOK"
    [ "$status" -ne 0 ]
    [[ "$output" == *"pytest-cov is not installed for python"* ]]
}

@test "pre-commit fails when python has no pytest" {
    touch pyproject.toml
    mock_command "ruff" 0
    cat > "${TEST_TMPDIR}/mocks/python" << 'EOF'
#!/bin/bash
case "$*" in "-c import pytest") exit 1 ;; esac
exit 0
EOF
    chmod +x "${TEST_TMPDIR}/mocks/python"
    run "$HOOK"
    [ "$status" -ne 0 ]
    [[ "$output" == *"pytest is not installed for python"* ]]
}

@test "pre-commit uses --select ALL when project has no ruff config" {
    printf '[project]\nname = "x"\n' > pyproject.toml
    _mock_python_tools
    run "$HOOK"
    [[ "$output" == *"ruff check --select ALL ."* ]]
}

@test "pre-commit respects [tool.ruff] in pyproject.toml" {
    printf '[project]\nname = "x"\n\n[tool.ruff.lint]\nselect = ["E"]\n' > pyproject.toml
    _mock_python_tools
    run "$HOOK"
    [[ "$output" == *"project ruff config"* ]]
    [[ "$output" != *"--select ALL"* ]]
}

@test "pre-commit respects ruff.toml" {
    touch pyproject.toml
    echo 'line-length = 100' > ruff.toml
    _mock_python_tools
    run "$HOOK"
    [[ "$output" == *"project ruff config"* ]]
}

@test "pre-commit header does not claim an organizational mandate" {
    ! grep -q "organizational security requirements" "$HOOK"
}

# ─── Staged snapshot ───────────────────────────────────────────────────

# python mock: the coverage run fails unless module.py holds "good" in the
# folder being checked; every other python call succeeds
_mock_python_needs_module() {
    mock_command "ruff" 0
    cat > "${TEST_TMPDIR}/mocks/python" << 'EOF'
#!/bin/bash
case "$*" in
    "-m pytest"*) grep -qx good module.py 2>/dev/null || exit 1 ;;
esac
exit 0
EOF
    chmod +x "${TEST_TMPDIR}/mocks/python"
}

@test "pre-commit checks the staged snapshot, not untracked files" {
    git init -q
    touch pyproject.toml
    _mock_python_tools
    run "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Checking the staged snapshot"* ]]
    [[ "$output" != *"PYTHON QUALITY CHECKS"* ]]
    git add pyproject.toml
    run "$HOOK"
    [[ "$output" == *"PYTHON QUALITY CHECKS"* ]]
}

@test "pre-commit fails a commit whose staged files fail, even if the work tree passes" {
    git init -q
    touch pyproject.toml
    echo good > module.py
    _mock_python_needs_module
    git add pyproject.toml
    run "$HOOK"
    [ "$status" -ne 0 ]
    [[ "$output" == *"COVERAGE FAILED"* ]]
    git add module.py
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "pre-commit checks the staged version of a file, not its unstaged edits" {
    git init -q
    touch pyproject.toml
    echo good > module.py
    git add pyproject.toml module.py
    echo bad > module.py
    _mock_python_needs_module
    run "$HOOK"
    [ "$status" -eq 0 ]
    echo good > module.py
    git add module.py
    echo bad > module.py
    git add module.py
    echo good > module.py
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "pre-commit leaves the work tree untouched and removes its snapshot" {
    git init -q
    touch pyproject.toml
    echo good > module.py
    git add pyproject.toml module.py
    echo edited > module.py
    echo draft > notes.txt
    before="$(git status --porcelain; cat module.py notes.txt)"
    _mock_python_tools
    run "$HOOK"
    [ "$status" -eq 0 ]
    [ "$(git status --porcelain; cat module.py notes.txt)" = "$before" ]
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "pre-commit removes its snapshot when a check fails" {
    git init -q
    touch pyproject.toml
    git add pyproject.toml
    _mock_python_needs_module
    run "$HOOK"
    [ "$status" -ne 0 ]
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "pre-commit reuses installed dependencies that are never staged" {
    git init -q
    touch pyproject.toml
    git add pyproject.toml
    mkdir .venv
    mock_command "ruff" 0
    cat > "${TEST_TMPDIR}/mocks/python" << 'EOF'
#!/bin/bash
case "$*" in "-m pytest"*) [ -d .venv ] || exit 1 ;; esac
exit 0
EOF
    chmod +x "${TEST_TMPDIR}/mocks/python"
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "pre-commit points Rust builds at the project's target folder" {
    git init -q
    touch Cargo.toml
    git add Cargo.toml
    mock_command "cargo-llvm-cov" 0
    cat > "${TEST_TMPDIR}/mocks/cargo" << EOF
#!/bin/bash
echo "\$CARGO_TARGET_DIR" > "${TEST_TMPDIR}/target.log"
exit 0
EOF
    chmod +x "${TEST_TMPDIR}/mocks/cargo"
    run "$HOOK"
    [ "$status" -eq 0 ]
    [ "$(cat "${TEST_TMPDIR}/target.log")" = "$(pwd -P)/target" ]
}

@test "pre-commit checks a partial commit's own index" {
    git init -q
    touch pyproject.toml
    echo bad > module.py
    git add pyproject.toml module.py
    echo good > module.py
    _mock_python_needs_module
    # git commit module.py builds a temporary index and points GIT_INDEX_FILE at it
    cp .git/index "${TEST_TMPDIR}/partial-index"
    GIT_INDEX_FILE="${TEST_TMPDIR}/partial-index" git add module.py
    GIT_INDEX_FILE="${TEST_TMPDIR}/partial-index" run "$HOOK"
    [ "$status" -eq 0 ]
    run "$HOOK"
    [ "$status" -ne 0 ]
}

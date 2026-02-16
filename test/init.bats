#!/usr/bin/env bats

load test_helper

setup() {
    setup_tmpdir
    setup_project "myapp"
}

teardown() {
    teardown_tmpdir
}

# ─── Basic init ──────────────────────────────────────────────────────────

@test "init creates .asimov/ directory" {
    git init -q .
    run "$ASIMOV_BIN" init
    [ "$status" -eq 0 ]
    [ -d .asimov ]
}

@test "init creates project.yaml with project name" {
    git init -q .
    run "$ASIMOV_BIN" init myapp
    [ "$status" -eq 0 ]
    [ -f .asimov/project.yaml ]
    run yq -r '.identity.name' .asimov/project.yaml
    [ "$output" = "myapp" ]
}

@test "init uses directory name when no name given" {
    git init -q .
    run "$ASIMOV_BIN" init
    [ "$status" -eq 0 ]
    run yq -r '.identity.name' .asimov/project.yaml
    [ "$output" = "myapp" ]
}

@test "init creates roadmap.yaml" {
    git init -q .
    run "$ASIMOV_BIN" init
    [ "$status" -eq 0 ]
    [ -f .asimov/roadmap.yaml ]
    run yq -r '.current.version' .asimov/roadmap.yaml
    [ "$output" = "0.1.0" ]
}

@test "init copies all four protocols" {
    git init -q .
    run "$ASIMOV_BIN" init
    [ "$status" -eq 0 ]
    [ -f .asimov/freshness.json ]
    [ -f .asimov/sycophancy.json ]
    [ -f .asimov/sprint.json ]
    [ -f .asimov/coding-standards.json ]
}

@test "init generates project.yaml with description, stack, conventions" {
    git init -q .
    run "$ASIMOV_BIN" init myapp
    [ "$status" -eq 0 ]
    run yq -r '.description' .asimov/project.yaml
    [ "$output" = "TODO: describe your project" ]
    run yq -r '.stack | length' .asimov/project.yaml
    [ "$output" = "0" ]
    run yq -r '.conventions | length' .asimov/project.yaml
    [ "$output" = "0" ]
}

# ─── Type detection ──────────────────────────────────────────────────────

@test "init detects rust project" {
    git init -q .
    touch Cargo.toml
    run "$ASIMOV_BIN" init
    [ "$status" -eq 0 ]
    run yq -r '.identity.type' .asimov/project.yaml
    [ "$output" = "rust" ]
}

@test "init detects node project" {
    git init -q .
    echo '{}' > package.json
    run "$ASIMOV_BIN" init
    [ "$status" -eq 0 ]
    run yq -r '.identity.type' .asimov/project.yaml
    [ "$output" = "node" ]
}

@test "init detects python project (pyproject.toml)" {
    git init -q .
    touch pyproject.toml
    run "$ASIMOV_BIN" init
    [ "$status" -eq 0 ]
    run yq -r '.identity.type' .asimov/project.yaml
    [ "$output" = "python" ]
}

@test "init detects python project (setup.py)" {
    git init -q .
    touch setup.py
    run "$ASIMOV_BIN" init
    [ "$status" -eq 0 ]
    run yq -r '.identity.type' .asimov/project.yaml
    [ "$output" = "python" ]
}

@test "init detects go project" {
    git init -q .
    touch go.mod
    run "$ASIMOV_BIN" init
    [ "$status" -eq 0 ]
    run yq -r '.identity.type' .asimov/project.yaml
    [ "$output" = "go" ]
}

@test "init detects flutter project" {
    git init -q .
    touch pubspec.yaml
    run "$ASIMOV_BIN" init
    [ "$status" -eq 0 ]
    run yq -r '.identity.type' .asimov/project.yaml
    [ "$output" = "flutter" ]
}

@test "init defaults to generic type" {
    git init -q .
    run "$ASIMOV_BIN" init
    [ "$status" -eq 0 ]
    run yq -r '.identity.type' .asimov/project.yaml
    [ "$output" = "generic" ]
}

# ─── Pre-commit hook ────────────────────────────────────────────────────

@test "init installs pre-commit hook in git repo" {
    git init -q .
    run "$ASIMOV_BIN" init
    [ "$status" -eq 0 ]
    [ -f .git/hooks/pre-commit ]
    [ -x .git/hooks/pre-commit ]
}

@test "init warns when not a git repo" {
    run "$ASIMOV_BIN" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"not a git repo"* ]]
}

# ─── Idempotence / guard ────────────────────────────────────────────────

@test "init fails if .asimov/ already exists" {
    git init -q .
    mkdir -p .asimov
    run "$ASIMOV_BIN" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

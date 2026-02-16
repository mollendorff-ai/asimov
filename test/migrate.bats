#!/usr/bin/env bats

load test_helper

setup() {
    setup_tmpdir
    setup_project "migratetest"
}

teardown() {
    teardown_tmpdir
}

# ─── No .asimov/ ────────────────────────────────────────────────────────

@test "migrate fails when no .asimov/ exists" {
    run "$ASIMOV_BIN" migrate
    [ "$status" -eq 1 ]
    [[ "$output" == *"No .asimov/ directory found"* ]]
}

# ─── Cruft removal ──────────────────────────────────────────────────────

@test "migrate removes old cruft files" {
    mkdir -p .asimov
    touch .asimov/project.yaml
    for f in warmup.json asimov.json green.json migrations.json; do
        echo '{}' > ".asimov/${f}"
    done

    run "$ASIMOV_BIN" migrate
    [ "$status" -eq 0 ]
    [ ! -f .asimov/warmup.json ]
    [ ! -f .asimov/asimov.json ]
    [ ! -f .asimov/green.json ]
    [ ! -f .asimov/migrations.json ]
}

@test "migrate removes old cruft directories" {
    mkdir -p .asimov/roles .asimov/templates .asimov/hooks .asimov/protocols
    touch .asimov/project.yaml

    run "$ASIMOV_BIN" migrate
    [ "$status" -eq 0 ]
    [ ! -d .asimov/roles ]
    [ ! -d .asimov/templates ]
    [ ! -d .asimov/hooks ]
    [ ! -d .asimov/protocols ]
}

@test "migrate removes old bootstrap files from project root" {
    mkdir -p .asimov
    touch .asimov/project.yaml
    touch CLAUDE.md GEMINI.md CODEX.md

    run "$ASIMOV_BIN" migrate
    [ "$status" -eq 0 ]
    [ ! -f CLAUDE.md ]
    [ ! -f GEMINI.md ]
    [ ! -f CODEX.md ]
}

# ─── Slim project.yaml ──────────────────────────────────────────────────

@test "migrate removes legacy keys and adds new fields to project.yaml" {
    mkdir -p .asimov
    cat > .asimov/project.yaml << 'YAML'
identity:
  name: bigproj
  type: rust
quality:
  coverage: 100
files:
  main: src/main.rs
YAML

    run "$ASIMOV_BIN" migrate
    [ "$status" -eq 0 ]
    # Legacy keys removed
    run yq -e '.quality' .asimov/project.yaml
    [ "$status" -ne 0 ]
    run yq -e '.files' .asimov/project.yaml
    [ "$status" -ne 0 ]
    # Identity preserved
    run yq -r '.identity.name' .asimov/project.yaml
    [ "$output" = "bigproj" ]
    # New fields added
    run yq -r '.description' .asimov/project.yaml
    [ "$output" = "TODO: describe your project" ]
    run yq -e '.stack' .asimov/project.yaml
    [ "$status" -eq 0 ]
    run yq -e '.conventions' .asimov/project.yaml
    [ "$status" -eq 0 ]
}

@test "migrate leaves fully enriched project.yaml untouched" {
    mkdir -p .asimov
    cat > .asimov/project.yaml << 'YAML'
identity:
  name: slimproj
  type: node
description: "A cool project"
stack: []
conventions: []
YAML
    cat > .asimov/roadmap.yaml << 'YAML'
current:
  version: "1.0.0"
  status: released
YAML
    cp "${PROJECT_ROOT}/protocols/"*.json .asimov/

    run "$ASIMOV_BIN" migrate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already up to date"* ]]
}

# ─── Protocol restoration ───────────────────────────────────────────────

@test "migrate adds missing protocols" {
    mkdir -p .asimov
    cat > .asimov/project.yaml << 'YAML'
identity:
  name: noproto
  type: shell
YAML

    run "$ASIMOV_BIN" migrate
    [ "$status" -eq 0 ]
    [ -f .asimov/freshness.json ]
    [ -f .asimov/sycophancy.json ]
    [ -f .asimov/sprint.json ]
    [ -f .asimov/coding-standards.json ]
}

@test "migrate does not overwrite existing protocols" {
    mkdir -p .asimov
    cat > .asimov/project.yaml << 'YAML'
identity:
  name: customproto
  type: shell
YAML
    echo '{"rule":"custom"}' > .asimov/freshness.json
    cp "${PROJECT_ROOT}/protocols/sycophancy.json" .asimov/
    cp "${PROJECT_ROOT}/protocols/sprint.json" .asimov/
    cp "${PROJECT_ROOT}/protocols/coding-standards.json" .asimov/

    run "$ASIMOV_BIN" migrate
    [ "$status" -eq 0 ]
    # Custom freshness should be preserved
    run jq -r '.rule' .asimov/freshness.json
    [ "$output" = "custom" ]
}

# ─── Pre-commit hook update ─────────────────────────────────────────────

@test "migrate updates pre-commit hook in git repo" {
    git init -q .
    mkdir -p .asimov
    cat > .asimov/project.yaml << 'YAML'
identity:
  name: hooktest
  type: shell
YAML

    run "$ASIMOV_BIN" migrate
    [ "$status" -eq 0 ]
    [ -f .git/hooks/pre-commit ]
    [ -x .git/hooks/pre-commit ]
}

# ─── Orphan detection ───────────────────────────────────────────────────

@test "migrate warns about unexpected files" {
    mkdir -p .asimov
    cat > .asimov/project.yaml << 'YAML'
identity:
  name: orphantest
  type: shell
YAML
    # Copy standard protocols so they don't trigger "added" messages
    cp "${PROJECT_ROOT}/protocols/"*.json .asimov/
    # Create an orphan
    echo "stale" > .asimov/old-stuff.txt

    run "$ASIMOV_BIN" migrate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unexpected files"* ]]
    [[ "$output" == *"old-stuff.txt"* ]]
}

# ─── Already up to date ─────────────────────────────────────────────────

@test "migrate reports up to date when nothing to do" {
    mkdir -p .asimov
    cat > .asimov/project.yaml << 'YAML'
identity:
  name: cleanproj
  type: shell
description: "A clean project"
stack: []
conventions: []
YAML
    cat > .asimov/roadmap.yaml << 'YAML'
current:
  version: "1.0.0"
  status: released
YAML
    cp "${PROJECT_ROOT}/protocols/"*.json .asimov/

    run "$ASIMOV_BIN" migrate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already up to date"* ]]
}

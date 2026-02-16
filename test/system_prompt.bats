#!/usr/bin/env bats

load test_helper

setup() {
    setup_tmpdir
    setup_project "prompttest"
    source_asimov_functions
}

teardown() {
    teardown_tmpdir
}

# ─── build_system_prompt ─────────────────────────────────────────────────

@test "build_system_prompt returns empty when no .asimov/" {
    run build_system_prompt
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "build_system_prompt produces valid JSON" {
    create_test_asimov_dir
    run build_system_prompt
    [ "$status" -eq 0 ]
    # Must be valid JSON
    echo "$output" | jq . >/dev/null 2>&1
}

@test "build_system_prompt includes project identity" {
    create_test_asimov_dir
    run build_system_prompt
    [ "$status" -eq 0 ]
    local name
    name=$(echo "$output" | jq -r '.project.name')
    [ "$name" = "testproj" ]
    local type
    type=$(echo "$output" | jq -r '.project.type')
    [ "$type" = "shell" ]
}

@test "build_system_prompt includes protocol rules" {
    create_test_asimov_dir
    run build_system_prompt
    [ "$status" -eq 0 ]

    local freshness
    freshness=$(echo "$output" | jq -r '.protocols.freshness')
    [[ "$freshness" == *"ref fetch"* ]]

    local sycophancy
    sycophancy=$(echo "$output" | jq -r '.protocols.sycophancy')
    [[ "$sycophancy" == *"accuracy and honesty"* ]]

    local sprint
    sprint=$(echo "$output" | jq -r '.protocols.sprint')
    [[ "$sprint" == *"autonomous"* ]]

    local coding_standards
    coding_standards=$(echo "$output" | jq -r '.protocols.coding_standards')
    [ -n "$coding_standards" ]
}

@test "build_system_prompt handles missing protocols gracefully" {
    mkdir -p .asimov
    cat > .asimov/project.yaml << 'YAML'
identity:
  name: noproto
  type: shell
YAML
    # No protocol files

    run build_system_prompt
    [ "$status" -eq 0 ]
    # Should still produce JSON with empty protocol values
    local name
    name=$(echo "$output" | jq -r '.project.name')
    [ "$name" = "noproto" ]
    local freshness
    freshness=$(echo "$output" | jq -r '.protocols.freshness')
    [ "$freshness" = "" ]
}

@test "build_system_prompt is compact (single line)" {
    create_test_asimov_dir
    run build_system_prompt
    [ "$status" -eq 0 ]
    # jq -c produces single-line output; no newlines in the result
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    [ "$line_count" -eq 1 ]
}

@test "build_system_prompt returns empty when only empty project.yaml" {
    mkdir -p .asimov
    touch .asimov/project.yaml
    # No name, no protocols → nothing to inject
    run build_system_prompt
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

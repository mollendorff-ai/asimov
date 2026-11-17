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

# ─── current sprint ──────────────────────────────────────────────────────

@test "build_system_prompt includes the current sprint from the roadmap" {
    create_test_asimov_dir
    cat > .asimov/roadmap.yaml << 'YAML'
current:
  version: "2.0.0"
  title: "Ship it"
  status: autonomous
  deliverables:
    - "first thing"
    - "second thing"
backlog:
  - version: "2.1.0"
    title: "later"
YAML
    run build_system_prompt
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.current_sprint.version')" = "2.0.0" ]
    [ "$(echo "$output" | jq -r '.current_sprint.title')" = "Ship it" ]
    [ "$(echo "$output" | jq -r '.current_sprint.status')" = "autonomous" ]
    [ "$(echo "$output" | jq -r '.current_sprint.deliverables | length')" -eq 2 ]
    [[ "$output" != *"later"* ]]
}

@test "build_system_prompt leaves out the sprint when the roadmap has no current milestone" {
    create_test_asimov_dir
    printf 'backlog: []\n' > .asimov/roadmap.yaml
    run build_system_prompt
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq 'has("current_sprint")')" = "false" ]
}

@test "build_system_prompt leaves out the sprint when there is no roadmap" {
    create_test_asimov_dir
    rm .asimov/roadmap.yaml
    run build_system_prompt
    [ "$(echo "$output" | jq 'has("current_sprint")')" = "false" ]
}

@test "build_system_prompt gives the sprint alone when it is all there is" {
    mkdir -p .asimov
    printf 'current:\n  version: "0.1.0"\n  title: "Only this"\n' > .asimov/roadmap.yaml
    run build_system_prompt
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.current_sprint.title')" = "Only this" ]
}

@test "sprint_summary prints one line, and nothing without a roadmap" {
    create_test_asimov_dir
    printf 'current:\n  version: "3.3.0"\n  title: "Upgrades"\n  status: pending\n  deliverables: [a, b, c]\n' > .asimov/roadmap.yaml
    run sprint_summary
    [ "$output" = "Sprint: 3.3.0 Upgrades [pending], 3 deliverable(s)" ]
    rm .asimov/roadmap.yaml
    run sprint_summary
    [ "$output" = "" ]
}

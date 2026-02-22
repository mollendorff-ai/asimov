#!/usr/bin/env bats

load test_helper

setup() {
    setup_tmpdir
    # source_asimov_functions sets ASIMOV_GLOBAL_DIR from HOME,
    # so it must run after setup_tmpdir fakes HOME
    source_asimov_functions
    # Re-derive globals from the now-faked HOME
    ASIMOV_GLOBAL_DIR="${HOME}/.asimov"
    ASIMOV_GLOBAL_CONFIG="${ASIMOV_GLOBAL_DIR}/config.yaml"
}

teardown() {
    teardown_tmpdir
}

# ─── No config file ─────────────────────────────────────────────────────

@test "migrate_global_config returns 0 when no config file exists" {
    run migrate_global_config
    [ "$status" -eq 0 ]
}

# ─── Injects missing env vars ───────────────────────────────────────────

@test "migrate_global_config adds CLAUDE_CODE_EFFORT_LEVEL to old config" {
    create_test_config
    run migrate_global_config
    [ "$status" -eq 0 ]
    run yq -r '.launch.claude.env.CLAUDE_CODE_EFFORT_LEVEL' "$ASIMOV_GLOBAL_CONFIG"
    [ "$output" = "max" ]
}

@test "migrate_global_config adds CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS to old config" {
    create_test_config
    run migrate_global_config
    [ "$status" -eq 0 ]
    run yq -r '.launch.claude.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$ASIMOV_GLOBAL_CONFIG"
    [ "$output" = "1" ]
}

# ─── Preserves existing values ──────────────────────────────────────────

@test "migrate_global_config does not overwrite existing CLAUDE_CODE_EFFORT_LEVEL" {
    create_test_config
    yq -i '.launch.claude.env.CLAUDE_CODE_EFFORT_LEVEL = "low"' "$ASIMOV_GLOBAL_CONFIG"
    run migrate_global_config
    [ "$status" -eq 0 ]
    run yq -r '.launch.claude.env.CLAUDE_CODE_EFFORT_LEVEL' "$ASIMOV_GLOBAL_CONFIG"
    [ "$output" = "low" ]
}

@test "migrate_global_config does not overwrite existing CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" {
    create_test_config
    yq -i '.launch.claude.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "0"' "$ASIMOV_GLOBAL_CONFIG"
    run migrate_global_config
    [ "$status" -eq 0 ]
    run yq -r '.launch.claude.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$ASIMOV_GLOBAL_CONFIG"
    [ "$output" = "0" ]
}

# ─── Preserves other config ─────────────────────────────────────────────

@test "migrate_global_config preserves MAX_THINKING_TOKENS" {
    create_test_config
    run migrate_global_config
    [ "$status" -eq 0 ]
    run yq -r '.launch.claude.env.MAX_THINKING_TOKENS' "$ASIMOV_GLOBAL_CONFIG"
    [ "$output" = "1000000" ]
}

@test "migrate_global_config preserves model and args" {
    create_test_config
    run migrate_global_config
    [ "$status" -eq 0 ]
    run yq -r '.launch.claude.model' "$ASIMOV_GLOBAL_CONFIG"
    [ "$output" = "opus" ]
    run yq -r '.launch.claude.args[0]' "$ASIMOV_GLOBAL_CONFIG"
    [ "$output" = "--dangerously-skip-permissions" ]
}

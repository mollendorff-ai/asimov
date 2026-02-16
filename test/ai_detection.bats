#!/usr/bin/env bats

load test_helper

setup() {
    setup_tmpdir
    # Save real env vars that Claude Code sets, then unset for testing
    _SAVED_CLAUDECODE="${CLAUDECODE:-}"
    _SAVED_CLAUDE_CODE_ENTRYPOINT="${CLAUDE_CODE_ENTRYPOINT:-}"
    _SAVED_GEMINI_CLI="${GEMINI_CLI:-}"
    _SAVED_CODEX_CLI="${CODEX_CLI:-}"
    unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT GEMINI_CLI CODEX_CLI 2>/dev/null || true
    source_asimov_functions
    # Build a clean PATH for detect_ai tests that includes system tools
    # but hides real AI CLIs (claude lives in /opt/homebrew/bin alongside yq)
    MOCK_DIR="${TEST_TMPDIR}/mocks"
    SAFE_DIR="${TEST_TMPDIR}/safe_bin"
    mkdir -p "$MOCK_DIR" "$SAFE_DIR"
    # Symlink only the tools we need from homebrew
    for tool in yq jq git bash; do
        local p
        p=$(command -v "$tool" 2>/dev/null) && ln -sf "$p" "${SAFE_DIR}/"
    done
    SYS_PATH="/usr/bin:/bin:${SAFE_DIR}"
}

teardown() {
    [ -n "$_SAVED_CLAUDECODE" ] && export CLAUDECODE="$_SAVED_CLAUDECODE"
    [ -n "$_SAVED_CLAUDE_CODE_ENTRYPOINT" ] && export CLAUDE_CODE_ENTRYPOINT="$_SAVED_CLAUDE_CODE_ENTRYPOINT"
    [ -n "$_SAVED_GEMINI_CLI" ] && export GEMINI_CLI="$_SAVED_GEMINI_CLI"
    [ -n "$_SAVED_CODEX_CLI" ] && export CODEX_CLI="$_SAVED_CODEX_CLI"
    teardown_tmpdir
}

# Helper: create a stub executable in MOCK_DIR
_add_mock_cli() {
    printf '#!/bin/bash\nexit 0\n' > "${MOCK_DIR}/$1"
    chmod +x "${MOCK_DIR}/$1"
}

# ─── is_inside_session ───────────────────────────────────────────────────

@test "is_inside_session detects Claude Code via CLAUDECODE" {
    export CLAUDECODE=1
    run is_inside_session
    [ "$status" -eq 0 ]
    [ "$output" = "Claude Code" ]
}

@test "is_inside_session detects Claude Code via CLAUDE_CODE_ENTRYPOINT" {
    export CLAUDE_CODE_ENTRYPOINT=cli
    run is_inside_session
    [ "$status" -eq 0 ]
    [ "$output" = "Claude Code" ]
}

@test "is_inside_session detects Gemini CLI" {
    export GEMINI_CLI=1
    run is_inside_session
    [ "$status" -eq 0 ]
    [ "$output" = "Gemini CLI" ]
}

@test "is_inside_session detects Codex CLI" {
    export CODEX_CLI=1
    run is_inside_session
    [ "$status" -eq 0 ]
    [ "$output" = "Codex CLI" ]
}

@test "is_inside_session returns 1 when not in any session" {
    run is_inside_session
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

# ─── detect_ai ───────────────────────────────────────────────────────────

@test "detect_ai finds single installed AI CLI" {
    _add_mock_cli "claude"
    export PATH="${MOCK_DIR}:${SYS_PATH}"
    run detect_ai
    [ "$status" -eq 0 ]
    [ "$output" = "claude" ]
}

@test "detect_ai finds gemini when only gemini available" {
    _add_mock_cli "gemini"
    export PATH="${MOCK_DIR}:${SYS_PATH}"
    run detect_ai
    [ "$status" -eq 0 ]
    [ "$output" = "gemini" ]
}

@test "detect_ai exits 1 when no AI CLI found" {
    # MOCK_DIR exists but is empty — no AI CLIs
    export PATH="${MOCK_DIR}:${SYS_PATH}"
    run detect_ai
    [ "$status" -eq 1 ]
    [[ "$output" == *"No AI CLI found"* ]]
}

@test "detect_ai reports multiple CLIs when found" {
    _add_mock_cli "claude"
    _add_mock_cli "gemini"
    export PATH="${MOCK_DIR}:${SYS_PATH}"
    run detect_ai </dev/null
    [[ "$output" == *"Multiple AI CLIs found"* ]]
}

# ─── CLI dispatch ────────────────────────────────────────────────────────

@test "asimov --version prints version" {
    run "$ASIMOV_BIN" --version
    [ "$status" -eq 0 ]
    [[ "$output" == "asimov "* ]]
}

@test "asimov --help shows usage" {
    run "$ASIMOV_BIN" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE"* ]]
    [[ "$output" == *"asimov init"* ]]
    [[ "$output" == *"asimov migrate"* ]]
}

@test "asimov -h shows help" {
    run "$ASIMOV_BIN" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE"* ]]
}

@test "asimov unknown-command fails" {
    run "$ASIMOV_BIN" nonsense
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

# ─── ensure_global_config ────────────────────────────────────────────────

@test "ensure_global_config creates config on first run" {
    [ ! -d "$HOME/.asimov" ]
    ensure_global_config
    [ -f "$HOME/.asimov/config.yaml" ]
    run yq -r '.launch.default_ai' "$HOME/.asimov/config.yaml"
    [ "$output" = "claude" ]
}

@test "ensure_global_config is idempotent" {
    mkdir -p "$HOME/.asimov"
    echo "custom: true" > "$HOME/.asimov/config.yaml"
    ensure_global_config
    # Should NOT overwrite existing config
    run yq -r '.custom' "$HOME/.asimov/config.yaml"
    [ "$output" = "true" ]
}

# ─── check_deps ──────────────────────────────────────────────────────────

@test "check_deps passes when yq and jq are available" {
    run check_deps
    [ "$status" -eq 0 ]
}

#!/usr/bin/env bats

load test_helper

# End-to-end launch tests: run bin/asimov against mock AI CLIs that record
# their arguments, one argument per line, into $ARGS_LOG.

setup() {
    setup_tmpdir
    unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT GEMINI_CLI CODEX_CLI 2>/dev/null || true
    MOCK_DIR="${TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    # Keep yq/jq/coreutils, hide any real AI CLIs on the host
    local clean="$PATH"
    for cli in claude gemini codex; do
        clean="$(PATH="$clean" path_without "$cli")"
    done
    export PATH="${MOCK_DIR}:${clean}"
    ARGS_LOG="${TEST_TMPDIR}/args.log"
    export ARGS_LOG
    setup_project "launchproj"
    create_test_asimov_dir
}

teardown() {
    teardown_tmpdir
}

_mock_ai() {
    cat > "${MOCK_DIR}/$1" << 'EOF2'
#!/usr/bin/env bash
{ echo "---call"; for a in "$@"; do printf '%s\n' "$a"; done; } >> "$ARGS_LOG"
EOF2
    chmod +x "${MOCK_DIR}/$1"
}

_use_ai() {
    mkdir -p "$HOME/.asimov"
    printf 'launch:\n  default_ai: %s\n' "$1" > "$HOME/.asimov/config.yaml"
}

@test "claude: one launch with protocols and the sprint in the system prompt, no warmup turn" {
    _mock_ai claude
    _use_ai claude
    run "$ASIMOV_BIN"
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '---call' "$ARGS_LOG")" -eq 1 ]
    grep -qx -- '--append-system-prompt' "$ARGS_LOG"
    grep -q '"current_sprint"' "$ARGS_LOG"
    grep -qx -- '--dangerously-skip-permissions' "$ARGS_LOG"
    ! grep -qx -- '-p' "$ARGS_LOG"
    ! grep -qx -- '--continue' "$ARGS_LOG"
    [[ "$output" != *"Warming up"* ]]
}

@test "claude: prints the current sprint before launching" {
    _mock_ai claude
    _use_ai claude
    run "$ASIMOV_BIN"
    [[ "$output" == *"Sprint: 1.0.0 "*"[in_progress], 0 deliverable(s)"* ]]
}

@test "claude: launches without a sprint line when there is no roadmap" {
    rm .asimov/roadmap.yaml
    _mock_ai claude
    _use_ai claude
    run "$ASIMOV_BIN"
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '---call' "$ARGS_LOG")" -eq 1 ]
    [[ "$output" != *"Sprint:"* ]]
    ! grep -q '"current_sprint"' "$ARGS_LOG"
}

@test "claude: a roadmap that cannot be read does not stop the launch" {
    printf 'current: [unclosed\n  : :\n' > .asimov/roadmap.yaml
    _mock_ai claude
    _use_ai claude
    run "$ASIMOV_BIN"
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '---call' "$ARGS_LOG")" -eq 1 ]
    ! grep -q '"current_sprint"' "$ARGS_LOG"
}

@test "claude: the sprint's title and deliverables reach the prompt, capped at 12" {
    {
        printf 'current:\n  version: "3.3.0"\n  title: "upgrades reach projects"\n  status: pending\n  deliverables:\n'
        for i in $(seq 1 15); do printf '    - "deliverable number %s"\n' "$i"; done
    } > .asimov/roadmap.yaml
    _mock_ai claude
    _use_ai claude
    run "$ASIMOV_BIN"
    [ "$status" -eq 0 ]
    grep -q 'upgrades reach projects' "$ARGS_LOG"
    grep -q 'deliverable number 12' "$ARGS_LOG"
    ! grep -q 'deliverable number 13' "$ARGS_LOG"
    [[ "$output" == *"3.3.0 upgrades reach projects [pending], 15 deliverable(s)"* ]]
}

@test "gemini: protocols and the sprint sent via --prompt-interactive" {
    _mock_ai gemini
    _use_ai gemini
    run "$ASIMOV_BIN"
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '---call' "$ARGS_LOG")" -eq 1 ]
    grep -qx -- '--approval-mode=yolo' "$ARGS_LOG"
    grep -qx -- '--prompt-interactive' "$ARGS_LOG"
    grep -q 'Follow these project rules' "$ARGS_LOG"
    grep -q 'start on the current sprint' "$ARGS_LOG"
    grep -q '"current_sprint"' "$ARGS_LOG"
    grep -q 'sycophancy' "$ARGS_LOG"
    ! grep -q 'Read .asimov/roadmap.yaml' "$ARGS_LOG"
    ! grep -qx -- '--append-system-prompt' "$ARGS_LOG"
}

@test "codex: protocols and the sprint sent as the initial prompt" {
    _mock_ai codex
    _use_ai codex
    run "$ASIMOV_BIN"
    [ "$status" -eq 0 ]
    grep -qx -- '--full-auto' "$ARGS_LOG"
    grep -q 'Follow these project rules' "$ARGS_LOG"
    grep -q '"current_sprint"' "$ARGS_LOG"
    ! grep -q 'Read .asimov/roadmap.yaml' "$ARGS_LOG"
}

@test "gemini: does not mention a sprint when there is no roadmap" {
    rm .asimov/roadmap.yaml
    _mock_ai gemini
    _use_ai gemini
    run "$ASIMOV_BIN"
    [ "$status" -eq 0 ]
    grep -q 'Follow these project rules' "$ARGS_LOG"
    ! grep -q 'start on the current sprint' "$ARGS_LOG"
}

@test "gemini: launches with no extra prompt when there is no .asimov/" {
    rm -rf .asimov
    _mock_ai gemini
    _use_ai gemini
    run "$ASIMOV_BIN"
    [ "$status" -eq 0 ]
    ! grep -qx -- '--prompt-interactive' "$ARGS_LOG"
}

# ─── yq flavour ─────────────────────────────────────────────────────────

@test "launch refuses the Python yq with a clear message" {
    _mock_ai claude
    cat > "${MOCK_DIR}/yq" << 'EOF2'
#!/usr/bin/env bash
[ "$1" = "--version" ] && echo "yq 3.4.3" && exit 0
exit 2
EOF2
    chmod +x "${MOCK_DIR}/yq"
    run "$ASIMOV_BIN"
    [ "$status" -eq 1 ]
    [[ "$output" == *"needs mikefarah/yq"* ]]
    [ ! -f "$ARGS_LOG" ]
}

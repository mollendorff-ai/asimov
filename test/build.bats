#!/usr/bin/env bats

load test_helper

# Build mode (v3.0.0-alpha): ingest, preflight, plan, approval, scaffold.
# AI CLIs, ref and pandoc are mocks; the planner mock copies $MOCK_PLAN
# into plan.yaml so each test controls what "the agent" planned.

# PATH that keeps every host tool except the ones these tests mock, so a test
# can delete a mock and see the tool as missing (pandoc lives in /usr/bin).
setup_file() {
    local safe="${BATS_FILE_TMPDIR}/safe_bin" dir f name
    mkdir -p "$safe"
    local IFS=':'
    for dir in $PATH; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*; do
            name="${f##*/}"
            case "$name" in
                claude|gemini|codex|ref|pandoc) continue ;;
                # the quality gate's tools: present only as the mocks below
                cargo|cargo-llvm-cov|ruff|python|npm|go|gofumpt|golangci-lint|go-test-coverage|flutter|lcov) continue ;;
            esac
            [ -x "$f" ] && [ ! -e "${safe}/${name}" ] && ln -s "$f" "${safe}/${name}"
        done
    done
    export BUILD_SAFE_PATH="$safe"
}

setup() {
    setup_tmpdir
    unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT GEMINI_CLI CODEX_CLI 2>/dev/null || true
    unset MAX_THINKING_TOKENS CLAUDE_CODE_EFFORT_LEVEL 2>/dev/null || true
    MOCK_DIR="${TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="${MOCK_DIR}:${BUILD_SAFE_PATH}"
    export ARGS_LOG="${TEST_TMPDIR}/args.log"
    export MOCK_PLAN="${TEST_TMPDIR}/plan-fixture.yaml"
    export MOCK_REF_STATUS="ok"
    unset MOCK_NO_ASSUMPTIONS 2>/dev/null || true

    mkdir -p "$HOME/.asimov"
    printf 'launch:\n  default_ai: claude\nbuild:\n  sandbox: true\n' > "$HOME/.asimov/config.yaml"

    _mock_agent claude
    _mock_ref
    _mock_pandoc
    _mock_gate_tools
    _plan_one_project

    WORK="${TEST_TMPDIR}/work"
    mkdir -p "$WORK"
    cd "$WORK"
    printf '# Todo API\n\nA small REST API for todos.\n' > spec.md
}

teardown() {
    teardown_tmpdir
}

# Every tool the quality gate checks for, installed and working. A test makes
# one "missing" with rm "${MOCK_DIR}/<tool>"; none of them exist on the safe PATH.
_mock_gate_tools() {
    local t
    for t in cargo cargo-llvm-cov ruff python npm go gofumpt golangci-lint go-test-coverage flutter lcov; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "${MOCK_DIR}/${t}"
        chmod +x "${MOCK_DIR}/${t}"
    done
    # ruff fails on code the agent left unformatted: a bad.py where it runs
    # (the gate runs it in its copy of the staged or committed files)
    printf '#!/usr/bin/env bash\n[ -e bad.py ] && { echo "Would reformat: bad.py"; exit 1; }\nexit 0\n' > "${MOCK_DIR}/ruff"
}

# Agent mock: records args and env; in .asimov-build writes the plan
_mock_agent() {
    cat > "${MOCK_DIR}/$1" << 'EOF'
#!/usr/bin/env bash
{
    echo "---call $(basename "$0") in $(basename "$PWD")"
    for a in "$@"; do printf '%s\n' "$a"; done
    echo "env EFFORT=${CLAUDE_CODE_EFFORT_LEVEL:-unset} THINKING=${MAX_THINKING_TOKENS:-unset}"
} >> "$ARGS_LOG"
if [ "$(basename "$PWD")" = ".asimov-build" ]; then
    [ -f "$MOCK_PLAN" ] && cp "$MOCK_PLAN" plan.yaml
    [ -z "${MOCK_NO_ASSUMPTIONS:-}" ] && printf '# Assumptions\n\n- Storage: SQLite, simplest.\n- Auth: none in v0.1.\n' > ASSUMPTIONS.md
    [ -n "${MOCK_PLAN_COST:-}" ] && echo "{\"type\":\"result\",\"total_cost_usd\":${MOCK_PLAN_COST},\"is_error\":false}"
    exit "${MOCK_EXIT:-0}"
fi
# In a project: act like an agent working on the current milestone
_commit() { echo "$RANDOM" >> work.txt; git add -A >/dev/null; git commit -q --no-verify -m "work" >/dev/null; }
# Code that fails the quality gate, committed past the hook with --no-verify
_commit_bad() { touch pyproject.toml; echo "x=1" > bad.py; _commit; }
_release() { yq -i '.current.status = "released"' .asimov/roadmap.yaml; }
_move() { yq -i '.previous = {"version": .current.version, "title": .current.title} | .current = .backlog[0] | .backlog = .backlog[1:]' .asimov/roadmap.yaml; }
case "${MOCK_LOOP:-release}" in
    release) _commit; _release ;;
    move)    _commit; _move ;;
    bad)     _commit_bad; _release ;;
    bad_move) _commit_bad; _move ;;
    # fixed in the working tree only, never committed
    bad_dirty_fix) _commit_bad; rm bad.py; _release ;;
    # good code committed, junk left uncommitted
    good_dirty) rm -f bad.py; touch pyproject.toml; _commit; echo "x=1" > bad.py; _release ;;
    # bad code, and the project's own hook emptied so it would pass anything
    bad_hook) _commit_bad; printf '#!/bin/sh\nexit 0\n' > .git/hooks/pre-commit; _release ;;
    fix)     git rm -q --ignore-unmatch bad.py; _commit; _release ;;
    commit)  _commit ;;
    block)   echo "Need an API key for the payments sandbox." > BLOCKED.md ;;
    idle)    ;;
esac
echo '{"type":"result","total_cost_usd":0.25,"is_error":false}'
exit 0
EOF
    chmod +x "${MOCK_DIR}/$1"
}

_mock_ref() {
    cat > "${MOCK_DIR}/ref" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    fetch) url="${!#}"
           printf '{"url":"%s","status":"%s","title":"Remote spec","sections":[{"level":1,"heading":"Overview","content":"Fetched body."}],"code":[{"lang":"sh","source":"make run"}]}\n' "$url" "$MOCK_REF_STATUS" ;;
    check-links) [ -n "${MOCK_LINKS_FAIL:-}" ] && [ ! -f "${MOCK_LINKS_FIXED:-/nonexistent}" ] && { echo '{"broken":["https://dead.example"]}'; exit 1; }
           echo '{"broken":[]}' ;;
    pdf)   printf '{"url":"%s","status":"ok","title":"PDF spec","sections":[{"level":2,"heading":"Tables","content":"| a | b |\\n| - | - |\\n| 1 | 2 |"}]}\n' "$2" ;;
    *)     exit 0 ;;
esac
EOF
    chmod +x "${MOCK_DIR}/ref"
}

_mock_pandoc() {
    cat > "${MOCK_DIR}/pandoc" << 'EOF'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done
printf '# From docx\n\nConverted.\n' > "$out"
EOF
    chmod +x "${MOCK_DIR}/pandoc"
}

_plan_one_project() {
    cat > "$MOCK_PLAN" << 'EOF'
projects:
  - name: todo-api
    description: "A REST API for todos."
    stack: [rust]
    milestones:
      - version: "0.1.0"
        title: "CRUD endpoints"
        deliverables: ["GET/POST/DELETE /todos"]
        acceptance: ["POST then GET returns the todo"]
      - version: "0.2.0"
        title: "Persistence"
        deliverables: ["SQLite storage"]
        acceptance: ["Todos survive a restart"]
EOF
}

_plan_two_projects() {
    cat > "$MOCK_PLAN" << 'EOF'
projects:
  - name: todo-api
    description: "API"
    stack: [rust]
    milestones:
      - {version: "0.1.0", title: "API", deliverables: ["endpoints"], acceptance: ["tests pass"]}
  - name: todo-cli
    description: "CLI client"
    stack: [go]
    milestones:
      - {version: "0.1.0", title: "CLI", deliverables: ["commands"], acceptance: ["tests pass"]}
EOF
}

# ─── Preflight ──────────────────────────────────────────────────────────

@test "build refuses without the sandbox acknowledgement" {
    printf 'launch:\n  default_ai: claude\n' > "$HOME/.asimov/config.yaml"
    run "$ASIMOV_BIN" build spec.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"sandbox: true"* ]]
    [ ! -d .asimov-build ]
}

@test "build refuses with no specs" {
    run "$ASIMOV_BIN" build
    [ "$status" -eq 1 ]
    [[ "$output" == *"no specs given"* ]]
}

@test "build names ref as missing for a URL spec" {
    rm "${MOCK_DIR}/ref"
    run "$ASIMOV_BIN" build https://example.com/spec
    [ "$status" -eq 1 ]
    [[ "$output" == *"ref (for PDF and URL specs"* ]]
}

@test "build names pandoc as missing for a docx spec" {
    rm "${MOCK_DIR}/pandoc"
    touch spec.docx
    run "$ASIMOV_BIN" build spec.docx
    [ "$status" -eq 1 ]
    [[ "$output" == *"pandoc"* ]]
}

@test "build rejects an unsupported spec type" {
    touch spec.odt
    run "$ASIMOV_BIN" build spec.odt
    [ "$status" -eq 1 ]
    [[ "$output" == *"unsupported spec type"* ]]
}

@test "build refuses when a build already exists" {
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" build spec.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"asimov resume"* ]]
}

# ─── Ingest ─────────────────────────────────────────────────────────────

@test "build ingests md, txt, pdf, docx and URL specs as Markdown" {
    printf 'plain text spec\n' > notes.txt
    touch design.pdf brief.docx
    run "$ASIMOV_BIN" build spec.md notes.txt design.pdf brief.docx https://example.com/api-spec
    [ "$status" -eq 0 ]
    [ -f .asimov-build/specs/01-spec.md ]
    [ -f .asimov-build/specs/02-notes.md ]
    grep -q '^# PDF spec' .asimov-build/specs/03-design.md
    grep -q '| 1 | 2 |' .asimov-build/specs/03-design.md
    grep -q '^# From docx' .asimov-build/specs/04-brief.md
    grep -q '^## Overview' .asimov-build/specs/05-api-spec.md
    grep -q 'make run' .asimov-build/specs/05-api-spec.md
    [ "$(yq '.sources | length' .asimov-build/sources.yaml)" -eq 5 ]
}

@test "build stops before planning when a URL spec is behind a login" {
    export MOCK_REF_STATUS="login"
    run "$ASIMOV_BIN" build https://wiki.example.com/spec
    [ "$status" -eq 1 ]
    [[ "$output" == *"ref login https://wiki.example.com/spec"* ]]
    [[ "$output" == *"asimov resume"* ]]
    [ ! -f "$ARGS_LOG" ]
}

@test "resume re-reads specs after the login is fixed and plans" {
    export MOCK_REF_STATUS="login"
    run "$ASIMOV_BIN" build https://wiki.example.com/spec
    export MOCK_REF_STATUS="ok"
    run "$ASIMOV_BIN" resume
    [ "$status" -eq 0 ]
    [[ "$output" == *"asimov approve"* ]]
    [ "$(yq -r '.sources[0].status' .asimov-build/sources.yaml)" = "ok" ]
}

# ─── Plan and approval ──────────────────────────────────────────────────

@test "build stops for approval by default and scaffolds nothing" {
    run "$ASIMOV_BIN" build spec.md
    [ "$status" -eq 0 ]
    [[ "$output" == *"todo-api 0.1.0  CRUD endpoints"* ]]
    [[ "$output" == *"Assumptions: 2"* ]]
    [[ "$output" == *"asimov approve"* ]]
    [ "$(yq -r .phase .asimov-build/state.yaml)" = "awaiting_approval" ]
    [ ! -d todo-api ]
}

@test "plan runs claude headless with build defaults, not max thinking" {
    run "$ASIMOV_BIN" build spec.md
    grep -q -- '---call claude in .asimov-build' "$ARGS_LOG"
    grep -qx -- '-p' "$ARGS_LOG"
    grep -qx -- '--dangerously-skip-permissions' "$ARGS_LOG"
    grep -q 'env EFFORT=high THINKING=unset' "$ARGS_LOG"
}

@test "the planning run counts toward --max-usd and gets the budget" {
    MOCK_PLAN_COST=0.4 run "$ASIMOV_BIN" build --max-usd 5 spec.md
    [ "$status" -eq 0 ]
    grep -qx -- '--output-format' "$ARGS_LOG"
    grep -qx -- 'json' "$ARGS_LOG"
    grep -qx -- '--max-budget-usd' "$ARGS_LOG"
    grep -qx -- '5.00' "$ARGS_LOG"
    [ "$(yq -r .spent_usd .asimov-build/state.yaml)" = "0.4000" ]
}

@test "the planning run has no budget flag without --max-usd, but its cost is counted" {
    MOCK_PLAN_COST=0.25 run "$ASIMOV_BIN" build spec.md
    [ "$status" -eq 0 ]
    ! grep -qx -- '--max-budget-usd' "$ARGS_LOG"
    [ "$(yq -r .spent_usd .asimov-build/state.yaml)" = "0.2500" ]
}

@test "a planning run that fails still has its cost counted" {
    MOCK_PLAN_COST=0.3 MOCK_EXIT=1 run "$ASIMOV_BIN" build spec.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"planning run failed"* ]]
    [ "$(yq -r .spent_usd .asimov-build/state.yaml)" = "0.3000" ]
}

@test "resume does not plan again when the budget is already spent" {
    MOCK_PLAN_COST=0.4 MOCK_EXIT=1 run "$ASIMOV_BIN" build --max-usd 0.4 spec.md
    [ "$status" -ne 0 ]
    run "$ASIMOV_BIN" resume
    [ "$status" -ne 0 ]
    [[ "$output" == *"(--max-usd)"* ]]
}

# ─── Claude only ────────────────────────────────────────────────────────

@test "build --ai gemini is refused: build mode runs Claude only" {
    _mock_agent gemini
    run "$ASIMOV_BIN" build --ai gemini --dir g spec.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"build mode runs Claude only"* ]]
    [[ "$output" == *"'gemini'"* ]]
    [ ! -d g/.asimov-build ]
    [ ! -f "$ARGS_LOG" ]
}

@test "build --ai codex is refused: build mode runs Claude only" {
    _mock_agent codex
    run "$ASIMOV_BIN" build --ai codex --dir c spec.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"build mode runs Claude only"* ]]
    [ ! -d c/.asimov-build ]
    [ ! -f "$ARGS_LOG" ]
}

@test "build.default_ai set to another agent is refused and named" {
    printf 'build:\n  sandbox: true\n  default_ai: codex\n' > "$HOME/.asimov/config.yaml"
    run "$ASIMOV_BIN" build spec.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"'codex'"* ]]
}

@test "the interactive default agent does not decide which agent builds" {
    _mock_agent gemini
    printf 'launch:\n  default_ai: gemini\nbuild:\n  sandbox: true\n' > "$HOME/.asimov/config.yaml"
    run "$ASIMOV_BIN" build spec.md
    [ "$status" -eq 0 ]
    grep -q -- '---call claude' "$ARGS_LOG"
    ! grep -q -- '---call gemini' "$ARGS_LOG"
}

@test "resume refuses a build started with another agent and changes nothing" {
    run "$ASIMOV_BIN" build spec.md
    yq -i '.ai = "gemini" | .phase = "stopped"' .asimov-build/state.yaml
    before="$(cat .asimov-build/state.yaml)"
    run "$ASIMOV_BIN" resume --max-loops 9
    [ "$status" -eq 1 ]
    [[ "$output" == *"build mode runs Claude only"* ]]
    [[ "$output" == *"'gemini'"* ]]
    [ "$(cat .asimov-build/state.yaml)" = "$before" ]
}

@test "scaffold writes no Gemini settings" {
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ -f todo-api/.mcp.json ]
    [ ! -e todo-api/.gemini ]
}

@test "build --help says Claude is the only agent and counts planning in --max-usd" {
    run "$ASIMOV_BIN" build --help
    [[ "$output" == *"claude (the only agent build mode runs"* ]]
    [[ "$output" != *"gemini"* ]]
    [[ "$output" == *"planning included"* ]]
}

# ─── Quality-gate preflight ─────────────────────────────────────────────

_plan_stack() {
    cat > "$MOCK_PLAN" << EOF
projects:
  - name: demo
    description: "Demo."
    stack: [$1]
    milestones:
      - {version: "0.1.0", title: "First", deliverables: ["x"], acceptance: ["y"]}
EOF
}

# The agent calls so far: the plan is one, every build run is another
_agent_calls() { grep -c -- '---call claude' "$ARGS_LOG" || true; }

@test "preflight stops before any paid run when the Rust coverage tool is missing" {
    rm "${MOCK_DIR}/cargo-llvm-cov"
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"the quality gate needs tools that are not installed"* ]]
    [[ "$output" == *"todo-api (rust): cargo-llvm-cov"* ]]
    [[ "$output" == *"cargo install cargo-llvm-cov"* ]]
    [[ "$output" == *"asimov resume"* ]]
    [ ! -d todo-api ]
    [ "$(_agent_calls)" -eq 1 ]
    [ "$(yq -r .phase .asimov-build/state.yaml)" = "approved" ]
}

@test "resume continues once the missing tool is installed" {
    rm "${MOCK_DIR}/cargo-llvm-cov"
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$status" -eq 1 ]
    _mock_gate_tools
    run "$ASIMOV_BIN" resume --max-loops 0
    [ "$status" -eq 2 ]
    [ -d todo-api/.git ]
    [[ "$output" != *"not installed"* ]]
}

@test "preflight also guards build --yes" {
    rm "${MOCK_DIR}/cargo-llvm-cov"
    run "$ASIMOV_BIN" build --yes spec.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"cargo-llvm-cov"* ]]
    [ ! -d todo-api ]
    [ "$(_agent_calls)" -eq 1 ]
}

@test "preflight names a missing Rust component" {
    printf '#!/usr/bin/env bash\ncase "$*" in "clippy --version") exit 1 ;; esac\nexit 0\n' > "${MOCK_DIR}/cargo"
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"clippy"* ]]
    [[ "$output" == *"rustup component add clippy"* ]]
    [[ "$output" != *"rustfmt"* ]]
}

@test "preflight lists every missing Python tool at once" {
    _plan_stack "python, pytest"
    rm "${MOCK_DIR}/ruff"
    printf '#!/usr/bin/env bash\ncase "$*" in *pytest_cov*) exit 1 ;; esac\nexit 0\n' > "${MOCK_DIR}/python"
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"demo (python): ruff"* ]]
    [[ "$output" == *"pip install ruff"* ]]
    [[ "$output" == *"demo (python): pytest-cov (for python)"* ]]
    [[ "$output" != *"demo (python): pytest (for python)"* ]]
}

@test "preflight finds python without pytest" {
    _plan_stack "Python"
    printf '#!/usr/bin/env bash\ncase "$*" in "-c import pytest") exit 1 ;; esac\nexit 0\n' > "${MOCK_DIR}/python"
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"pytest (for python)"* ]]
}

@test "preflight checks each Go tool on its own" {
    _plan_stack "go"
    rm "${MOCK_DIR}/golangci-lint"
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"demo (go): golangci-lint"* ]]
    [[ "$output" != *"gofumpt"* ]]
    [[ "$output" != *"go-test-coverage"* ]]
}

@test "preflight checks Flutter and lcov" {
    _plan_stack "flutter"
    rm "${MOCK_DIR}/lcov"
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"demo (flutter): lcov"* ]]
}

@test "preflight needs only npm for Node" {
    _plan_stack "typescript"
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$status" -eq 2 ]
    rm "${MOCK_DIR}/npm"
    run "$ASIMOV_BIN" build --dir other spec.md
    run "$ASIMOV_BIN" approve other --max-loops 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"demo (node): npm"* ]]
}

@test "preflight checks every language a stack names" {
    _plan_stack "rust, python"
    rm "${MOCK_DIR}/cargo-llvm-cov" "${MOCK_DIR}/ruff"
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"demo (rust): cargo-llvm-cov"* ]]
    [[ "$output" == *"demo (python): ruff"* ]]
}

@test "preflight asks nothing for a stack with no known language" {
    _plan_stack "cobol, jcl"
    for t in cargo cargo-llvm-cov ruff python npm go gofumpt golangci-lint go-test-coverage flutter lcov; do
        rm -f "${MOCK_DIR}/${t}"
    done
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$status" -eq 2 ]
    [[ "$output" != *"not installed"* ]]
}

@test "preflight names the project in a two-project plan" {
    _plan_two_projects
    rm "${MOCK_DIR}/gofumpt"
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"todo-cli (go): gofumpt"* ]]
    [[ "$output" != *"todo-api"* ]]
    [ ! -d todo-api ]
}

@test "an invalid plan stops the build and names the problem" {
    sed -i.bak 's/name: todo-api/name: Todo API/' "$MOCK_PLAN"
    run "$ASIMOV_BIN" build spec.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"bad project name 'Todo API'"* ]]
    [ "$(yq -r .phase .asimov-build/state.yaml)" = "plan_invalid" ]
}

@test "a milestone without acceptance criteria is rejected" {
    yq -i 'del(.projects[0].milestones[1].acceptance)' "$MOCK_PLAN"
    run "$ASIMOV_BIN" build spec.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"1 milestone(s) missing"* ]]
}

@test "a plan without ASSUMPTIONS.md is rejected" {
    export MOCK_NO_ASSUMPTIONS=1
    run "$ASIMOV_BIN" build spec.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"ASSUMPTIONS.md was not written"* ]]
}

@test "a failed planning run stops with the log path" {
    export MOCK_EXIT=1
    run "$ASIMOV_BIN" build spec.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"planning run failed"* ]]
    [[ "$output" == *".asimov-build/logs/plan-"* ]]
}

@test "resume plans again after an invalid plan" {
    yq -i 'del(.projects[0].milestones)' "$MOCK_PLAN"
    run "$ASIMOV_BIN" build spec.md
    [ "$status" -eq 1 ]
    _plan_one_project
    run "$ASIMOV_BIN" resume
    [ "$status" -eq 0 ]
    [ "$(yq -r .phase .asimov-build/state.yaml)" = "awaiting_approval" ]
}

@test "approve refuses when there is nothing to approve" {
    run "$ASIMOV_BIN" approve
    [ "$status" -eq 1 ]
    [[ "$output" == *"no build in"* ]]
}

# ─── Scaffold ───────────────────────────────────────────────────────────

@test "approve scaffolds a git repo with .asimov/ from the plan" {
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$status" -eq 2 ]
    [ -d todo-api/.git ]
    [ -x todo-api/.git/hooks/pre-commit ]
    [ "$(yq -r .identity.name todo-api/.asimov/project.yaml)" = "todo-api" ]
    [ "$(yq -r .description todo-api/.asimov/project.yaml)" = "A REST API for todos." ]
    [ "$(yq -r '.stack[0]' todo-api/.asimov/project.yaml)" = "rust" ]
    [ "$(yq -r .current.version todo-api/.asimov/roadmap.yaml)" = "0.1.0" ]
    [ "$(yq -r .current.status todo-api/.asimov/roadmap.yaml)" = "autonomous" ]
    [ "$(yq -r '.backlog[0].version' todo-api/.asimov/roadmap.yaml)" = "0.2.0" ]
    [ -f todo-api/.asimov/sycophancy.json ]
    [ -f todo-api/docs/specs/01-spec.md ]
    [ -f todo-api/docs/ASSUMPTIONS.md ]
    [ "$(jq -r '.mcpServers.ref.args[0]' todo-api/.mcp.json)" = "mcp" ]
    [ "$(yq -r .phase .asimov-build/state.yaml)" = "stopped" ]
}

@test "scaffold records the project type from the plan's stack" {
    _plan_two_projects
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$(yq -r .identity.type todo-api/.asimov/project.yaml)" = "rust" ]
    [ "$(yq -r .identity.type todo-cli/.asimov/project.yaml)" = "go" ]
}

@test "scaffold finds the language anywhere in the stack, in any case" {
    cat > "$MOCK_PLAN" << 'EOF'
projects:
  - name: wordfreq
    description: "Counts words."
    stack: [Make, Python, pytest, ruff]
    milestones:
      - {version: "0.1.0", title: "Count", deliverables: ["count"], acceptance: ["tests pass"]}
EOF
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$(yq -r .identity.type wordfreq/.asimov/project.yaml)" = "python" ]
}

@test "scaffold keeps type generic when the stack names no known language" {
    cat > "$MOCK_PLAN" << 'EOF'
projects:
  - name: legacy
    description: "Old system."
    stack: [cobol, jcl]
    milestones:
      - {version: "0.1.0", title: "Port", deliverables: ["port"], acceptance: ["tests pass"]}
EOF
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ "$(yq -r .identity.type legacy/.asimov/project.yaml)" = "generic" ]
}

@test "scaffold log has no interactive-mode advice" {
    run "$ASIMOV_BIN" build spec.md
    run "$ASIMOV_BIN" approve --max-loops 0
    [ -f .asimov-build/logs/scaffold-todo-api.log ]
    grep -q "Initialized .asimov/ for 'todo-api' (rust)" .asimov-build/logs/scaffold-todo-api.log
    ! grep -q "Next:" .asimov-build/logs/scaffold-todo-api.log
}

@test "build --yes scaffolds without stopping" {
    run "$ASIMOV_BIN" build --yes --max-loops 0 spec.md
    [ "$status" -eq 2 ]
    [[ "$output" != *"asimov approve"* ]]
    [ -d todo-api/.asimov ]
}

@test "a two-project plan scaffolds two repos" {
    _plan_two_projects
    run "$ASIMOV_BIN" build --yes --max-loops 0 spec.md
    [ -d todo-api/.git ]
    [ -d todo-cli/.git ]
    [ "$(yq -r '.stack[0]' todo-cli/.asimov/project.yaml)" = "go" ]
}

@test "scaffold refuses to use a non-empty existing folder" {
    mkdir todo-api
    touch todo-api/keep.txt
    run "$ASIMOV_BIN" build --yes spec.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"exists and is not empty"* ]]
    [ -f todo-api/keep.txt ]
}

@test "no .mcp.json when ref is not installed" {
    rm "${MOCK_DIR}/ref"
    run "$ASIMOV_BIN" build --yes --max-loops 0 spec.md
    [ -d todo-api/.asimov ]
    [ ! -f todo-api/.mcp.json ]
}

@test "build --dir puts the build in another folder" {
    run "$ASIMOV_BIN" build --yes --max-loops 0 --dir out spec.md
    [ -d out/.asimov-build ]
    [ -d out/todo-api/.git ]
}

@test "build --help shows usage" {
    run "$ASIMOV_BIN" build --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"asimov approve"* ]]
}

# ─── Execute loop ───────────────────────────────────────────────────────

@test "execute builds every milestone and finishes" {
    run "$ASIMOV_BIN" build --yes spec.md
    [ "$status" -eq 0 ]
    [[ "$output" == *"todo-api 0.1.0: released"* ]]
    [[ "$output" == *"todo-api 0.2.0: released"* ]]
    [[ "$output" == *"Build done"* ]]
    [ "$(yq -r .phase .asimov-build/state.yaml)" = "done" ]
    [ "$(yq -r '.projects["todo-api"].loops' .asimov-build/state.yaml)" = "2" ]
    [ "$(yq -r .previous.version todo-api/.asimov/roadmap.yaml)" = "0.1.0" ]
    [ "$(git -C todo-api rev-list --count HEAD)" -eq 2 ]
}

@test "execute promotes the next milestone from the plan" {
    run "$ASIMOV_BIN" build --yes --max-loops 1 spec.md
    [ "$status" -eq 2 ]
    [ "$(yq -r .current.version todo-api/.asimov/roadmap.yaml)" = "0.2.0" ]
    [ "$(yq -r .current.status todo-api/.asimov/roadmap.yaml)" = "autonomous" ]
    [ "$(yq -r .previous.title todo-api/.asimov/roadmap.yaml)" = "CRUD endpoints" ]
    [ "$(yq '.backlog | length' todo-api/.asimov/roadmap.yaml)" -eq 0 ]
}

@test "execute accepts an agent that moved the milestone itself" {
    export MOCK_LOOP=move
    run "$ASIMOV_BIN" build --yes spec.md
    [ "$status" -eq 0 ]
    [ "$(yq -r .phase .asimov-build/state.yaml)" = "done" ]
}

@test "execute runs the agent with the loop prompt and protocols" {
    run "$ASIMOV_BIN" build --yes spec.md
    grep -q -- '---call claude in todo-api' "$ARGS_LOG"
    grep -qx -- '--output-format' "$ARGS_LOG"
    grep -qx -- '--append-system-prompt' "$ARGS_LOG"
    grep -q 'You are building this project unattended' "$ARGS_LOG"
}

@test "builds two projects one after the other" {
    _plan_two_projects
    run "$ASIMOV_BIN" build --yes spec.md
    [ "$status" -eq 0 ]
    local api cli
    api="$(grep -n -- '---call claude in todo-api' "$ARGS_LOG" | tail -1 | cut -d: -f1)"
    cli="$(grep -n -- '---call claude in todo-cli' "$ARGS_LOG" | head -1 | cut -d: -f1)"
    [ "$api" -lt "$cli" ]
}

@test "stop rule: stall after runs with no new commit" {
    export MOCK_LOOP=idle
    run "$ASIMOV_BIN" build --yes --stall 2 spec.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"2 runs in a row without a new commit"* ]]
    [ "$(yq -r .phase .asimov-build/state.yaml)" = "stopped" ]
    [ "$(grep -c -- '---call claude in todo-api' "$ARGS_LOG")" -eq 2 ]
}

@test "stop rule: loop cap" {
    export MOCK_LOOP=commit
    run "$ASIMOV_BIN" build --yes --max-loops 3 spec.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"reached 3 agent runs"* ]]
}

@test "stop rule: BLOCKED.md stops the build and names the file" {
    export MOCK_LOOP=block
    run "$ASIMOV_BIN" build --yes spec.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"blocked"* ]]
    [[ "$output" == *"BLOCKED.md"* ]]
}

@test "stop rule: spend cap stops once the cost is reached" {
    export MOCK_LOOP=commit
    run "$ASIMOV_BIN" build --yes --max-usd 0.5 spec.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"of \$0.5 (--max-usd)"* ]]
    [ "$(grep -c -- '---call claude in todo-api' "$ARGS_LOG")" -eq 2 ]
    grep -qx -- '--max-budget-usd' "$ARGS_LOG"
}

@test "stop rule: time cap" {
    run "$ASIMOV_BIN" build --yes --max-hours 0 spec.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"reached 0 hours"* ]]
}

@test "resume continues after a stall and finishes" {
    export MOCK_LOOP=idle
    run "$ASIMOV_BIN" build --yes --stall 1 spec.md
    [ "$status" -eq 2 ]
    export MOCK_LOOP=release
    run "$ASIMOV_BIN" resume
    [ "$status" -eq 0 ]
    [ "$(yq -r .phase .asimov-build/state.yaml)" = "done" ]
}

@test "resume after BLOCKED.md is removed continues" {
    export MOCK_LOOP=block
    run "$ASIMOV_BIN" build --yes spec.md
    rm todo-api/BLOCKED.md
    export MOCK_LOOP=release
    run "$ASIMOV_BIN" resume
    [ "$status" -eq 0 ]
    [[ "$output" == *"Build done"* ]]
}

@test "resume can raise a cap" {
    export MOCK_LOOP=release
    run "$ASIMOV_BIN" build --yes --max-loops 1 spec.md
    [ "$status" -eq 2 ]
    run "$ASIMOV_BIN" resume --max-loops 5
    [ "$status" -eq 0 ]
    [ "$(yq -r .caps.max_loops .asimov-build/state.yaml)" = "5" ]
}

@test "broken links send a released milestone back to the agent" {
    export MOCK_LINKS_FAIL=1
    export MOCK_LINKS_FIXED="${TEST_TMPDIR}/links-fixed"
    run "$ASIMOV_BIN" build --yes --max-loops 1 spec.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"broken links, sending back"* ]]
    [ "$(yq -r .current.version todo-api/.asimov/roadmap.yaml)" = "0.1.0" ]
    [ "$(yq -r .current.status todo-api/.asimov/roadmap.yaml)" = "autonomous" ]
    touch "$MOCK_LINKS_FIXED"
    run "$ASIMOV_BIN" resume --max-loops 10
    [ "$status" -eq 0 ]
    grep -q 'these links in README.md or docs/ are broken' "$ARGS_LOG"
}

# Quality gate re-run: an agent can commit with --no-verify (the mock always
# does), so Asimov runs the gate itself on HEAD before a milestone counts.

@test "gate: code committed past the hook sends the milestone back" {
    export MOCK_LOOP=bad
    run "$ASIMOV_BIN" build --yes --max-loops 1 spec.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"fails the quality gate, sending back"* ]]
    [[ "$output" != *"released"* ]]
    [ "$(yq -r .current.version todo-api/.asimov/roadmap.yaml)" = "0.1.0" ]
    [ "$(yq -r .current.status todo-api/.asimov/roadmap.yaml)" = "autonomous" ]
    [ "$(yq -r '.projects["todo-api"].milestone // 0' .asimov-build/state.yaml)" = "0" ]
    grep -q 'Would reformat: bad.py' .asimov-build/logs/gate-todo-api.log
}

@test "gate: the next run gets the gate output, and a fix releases" {
    export MOCK_LOOP=bad
    run "$ASIMOV_BIN" build --yes --max-loops 1 spec.md
    [ "$status" -eq 2 ]
    export MOCK_LOOP=fix
    run "$ASIMOV_BIN" resume --max-loops 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"Build done"* ]]
    grep -q 'fails the quality gate, so a commit skipped' "$ARGS_LOG"
    grep -q 'Never use git commit --no-verify' "$ARGS_LOG"
    grep -q 'Would reformat: bad.py' "$ARGS_LOG"
    [ "$(yq -r '.projects["todo-api"].gate_fails' .asimov-build/state.yaml)" = "0" ]
}

@test "gate: a fix left uncommitted does not count" {
    export MOCK_LOOP=bad_dirty_fix
    run "$ASIMOV_BIN" build --yes --max-loops 1 spec.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"fails the quality gate, sending back"* ]]
}

@test "gate: uncommitted junk does not block good committed code" {
    export MOCK_LOOP=good_dirty
    run "$ASIMOV_BIN" build --yes spec.md
    [ "$status" -eq 0 ]
    [[ "$output" == *"Build done"* ]]
    [ -e todo-api/bad.py ]
}

@test "gate: runs Asimov's hook, so emptying the project's hook does not help" {
    export MOCK_LOOP=bad_hook
    run "$ASIMOV_BIN" build --yes --max-loops 1 spec.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"fails the quality gate, sending back"* ]]
}

@test "gate: an agent that moved the milestone itself is moved back" {
    export MOCK_LOOP=bad_move
    run "$ASIMOV_BIN" build --yes --max-loops 1 spec.md
    [ "$status" -eq 2 ]
    [ "$(yq -r .current.version todo-api/.asimov/roadmap.yaml)" = "0.1.0" ]
    [ "$(yq -r .current.status todo-api/.asimov/roadmap.yaml)" = "autonomous" ]
}

@test "gate: failures in a row stop the build, and resume continues" {
    export MOCK_LOOP=bad
    run "$ASIMOV_BIN" build --yes --stall 2 spec.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"failed the quality gate 2 times in a row"* ]]
    [[ "$output" == *"gate-todo-api.log"* ]]
    [ "$(grep -c '^---call claude in todo-api' "$ARGS_LOG")" -eq 2 ]
    export MOCK_LOOP=fix
    run "$ASIMOV_BIN" resume
    [ "$status" -eq 0 ]
    [[ "$output" == *"Build done"* ]]
}

@test "gate: does not run when no release is claimed" {
    export MOCK_LOOP=commit
    run "$ASIMOV_BIN" build --yes --max-loops 1 spec.md
    [ "$status" -eq 2 ]
    [ ! -e .asimov-build/logs/gate-todo-api.log ]
}

@test "gate: a missing shipped hook stops the build instead of skipping it" {
    local data="${TEST_TMPDIR}/data"
    mkdir -p "$data"
    cp -R "${PROJECT_ROOT}/protocols" "$data/"
    export MOCK_LOOP=release
    ASIMOV_DATA="$data" run "$ASIMOV_BIN" build --yes spec.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"the quality gate is missing"* ]]
    [[ "$output" != *"Build done"* ]]
}

@test "scaffold gives repos a commit identity when git has none" {
    run "$ASIMOV_BIN" build --yes spec.md
    [ "$status" -eq 0 ]
    git -C todo-api config user.email
}

@test "caps must be numbers" {
    run "$ASIMOV_BIN" build --max-loops ten spec.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"whole numbers"* ]]
}

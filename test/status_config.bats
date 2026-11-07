#!/usr/bin/env bats

load test_helper

setup() {
    setup_tmpdir
    setup_project "proj"
    mkdir -p "$HOME/.asimov"
    printf 'launch:\n  default_ai: claude\n' > "$HOME/.asimov/config.yaml"
}

teardown() {
    teardown_tmpdir
}

# ─── status ─────────────────────────────────────────────────────────────

@test "status reports version, tools and config" {
    run "$ASIMOV_BIN" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"asimov "* ]]
    [[ "$output" == *"ok    jq"* ]]
    [[ "$output" == *"default AI: claude"* ]]
    [[ "$output" == *"build.sandbox not set"* ]]
}

@test "status flags the Python yq" {
    mock_command yq 0 "yq 3.4.3"
    run "$ASIMOV_BIN" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"yq is not mikefarah/yq v4"* ]]
    [[ "$output" == *"issue(s)"* ]]
}

@test "status checks a project's protocols, roadmap and hook" {
    git init -q .
    run "$ASIMOV_BIN" init
    run "$ASIMOV_BIN" status
    [[ "$output" == *"protocols: 4 of 4"* ]]
    [[ "$output" == *"project.yaml has no description"* ]]
    [[ "$output" == *"roadmap: 0.1.0 Initial setup [pending]"* ]]
    [[ "$output" == *"pre-commit hook up to date"* ]]
}

@test "status flags a missing protocol and an outdated hook" {
    git init -q .
    run "$ASIMOV_BIN" init
    rm .asimov/sprint.json
    echo "# changed" >> .git/hooks/pre-commit
    run "$ASIMOV_BIN" status
    [[ "$output" == *"missing protocols: sprint.json"* ]]
    [[ "$output" == *"pre-commit hook is out of date"* ]]
}

@test "status shows BLOCKED.md" {
    run "$ASIMOV_BIN" init
    echo "Need an API key" > BLOCKED.md
    run "$ASIMOV_BIN" status
    [[ "$output" == *"BLOCKED.md: Need an API key"* ]]
}

@test "status shows a stopped build with spend and progress" {
    mkdir -p .asimov-build
    cat > .asimov-build/state.yaml << 'YAML'
phase: stopped
ai: claude
stop_reason: "todo-api: reached 3 agent runs (--max-loops)"
spent_usd: "1.2500"
caps:
  max_usd: "5"
projects:
  todo-api:
    milestone: "1"
    loops: "3"
YAML
    cat > .asimov-build/plan.yaml << 'YAML'
projects:
  - name: todo-api
    milestones: [{version: "0.1.0"}, {version: "0.2.0"}]
YAML
    run "$ASIMOV_BIN" status
    [[ "$output" == *"phase: stopped (AI: claude)"* ]]
    [[ "$output" == *"stopped: todo-api: reached 3 agent runs"* ]]
    [[ "$output" == *"spent: \$1.2500 of \$5"* ]]
    [[ "$output" == *"todo-api: 1 of 2 milestones released, 3 runs"* ]]
}

# ─── config ─────────────────────────────────────────────────────────────

@test "config set and get a boolean" {
    run "$ASIMOV_BIN" config set build.sandbox true
    [ "$status" -eq 0 ]
    run "$ASIMOV_BIN" config get build.sandbox
    [ "$output" = "true" ]
    [ "$(yq '.build.sandbox | tag' "$HOME/.asimov/config.yaml")" = "!!bool" ]
}

@test "config set keeps lists as lists" {
    run "$ASIMOV_BIN" config set launch.claude.args '[--dangerously-skip-permissions, --verbose]'
    [ "$status" -eq 0 ]
    [ "$(yq '.launch.claude.args | length' "$HOME/.asimov/config.yaml")" -eq 2 ]
}

@test "config set handles keys with dashes and underscores" {
    run "$ASIMOV_BIN" config set build.claude.env.CLAUDE_CODE_EFFORT_LEVEL high
    [ "$status" -eq 0 ]
    [ "$(yq -r '.build.claude.env.CLAUDE_CODE_EFFORT_LEVEL' "$HOME/.asimov/config.yaml")" = "high" ]
}

@test "config set keeps the rest of the file" {
    run "$ASIMOV_BIN" config set launch.claude.model sonnet
    [ "$(yq -r '.launch.default_ai' "$HOME/.asimov/config.yaml")" = "claude" ]
}

@test "config get of a missing key fails cleanly" {
    run "$ASIMOV_BIN" config get launch.nothing.here
    [ "$status" -eq 1 ]
    [ "$output" = "config: launch.nothing.here is not set" ]
}

@test "config unset removes a key" {
    run "$ASIMOV_BIN" config set launch.claude.model sonnet
    run "$ASIMOV_BIN" config unset launch.claude.model
    [ "$status" -eq 0 ]
    run "$ASIMOV_BIN" config get launch.claude.model
    [ "$status" -eq 1 ]
}

@test "config rejects a bad key" {
    run "$ASIMOV_BIN" config set 'bad key' x
    [ "$status" -eq 1 ]
    [[ "$output" == *"bad key"* ]]
}

@test "config --project writes .asimov/launch.yaml" {
    mkdir .asimov
    run "$ASIMOV_BIN" config set launch.default_ai gemini --project
    [ "$status" -eq 0 ]
    [ "$(yq -r '.launch.default_ai' .asimov/launch.yaml)" = "gemini" ]
    [ "$(yq -r '.launch.default_ai' "$HOME/.asimov/config.yaml")" = "claude" ]
}

@test "config --project needs .asimov/" {
    run "$ASIMOV_BIN" config set launch.default_ai gemini --project
    [ "$status" -eq 1 ]
    [[ "$output" == *"asimov init"* ]]
}

@test "config creates the global config when missing" {
    rm -rf "$HOME/.asimov"
    run "$ASIMOV_BIN" config set build.sandbox true
    [ "$status" -eq 0 ]
    [ "$(yq -r '.launch.default_ai' "$HOME/.asimov/config.yaml")" = "claude" ]
    [ "$(yq -r '.build.sandbox' "$HOME/.asimov/config.yaml")" = "true" ]
}

@test "config with no action prints usage" {
    run "$ASIMOV_BIN" config
    [ "$status" -eq 0 ]
    [[ "$output" == *"asimov config set"* ]]
}

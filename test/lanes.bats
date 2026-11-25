#!/usr/bin/env bats

load test_helper

# Lanes: several sessions on one project, each in its own lane with its own
# roadmap. Launches use a mock claude that records its arguments, one per
# line, into $ARGS_LOG, and the lane it was given into $LANE_LOG.

setup() {
    setup_tmpdir
    unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT GEMINI_CLI CODEX_CLI ASIMOV_LANE 2>/dev/null || true
    MOCK_DIR="${TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    local clean="$PATH"
    for cli in claude gemini codex; do
        clean="$(PATH="$clean" path_without "$cli")"
    done
    export PATH="${MOCK_DIR}:${clean}"
    export ARGS_LOG="${TEST_TMPDIR}/args.log"
    export LANE_LOG="${TEST_TMPDIR}/lane.log"
    cat > "${MOCK_DIR}/claude" << 'EOF'
#!/usr/bin/env bash
{ echo "---call"; for a in "$@"; do printf '%s\n' "$a"; done; } >> "$ARGS_LOG"
printf '%s\n' "${ASIMOV_LANE:-}" > "$LANE_LOG"
EOF
    chmod +x "${MOCK_DIR}/claude"
    mkdir -p "$HOME/.asimov"
    printf 'launch:\n  default_ai: claude\n' > "$HOME/.asimov/config.yaml"
    setup_project "laneproj"
    create_test_asimov_dir
}

teardown() {
    teardown_tmpdir
}

# Three lanes; engine releases. Changelog fragments go in changelog.d/.
_lanes() {
    cat >> .asimov/project.yaml << 'YAML'
lanes:
  - id: engine
    title: "Engine"
    owns: ["src/", "Cargo.toml"]
    releases: true
  - id: docs
    title: "Manual"
    owns: ["docs/", "README.md"]
  - id: features
    title: "New features"
    owns: ["src/", "web/"]
shared: ["changelog.d/"]
changelog:
  fragments: changelog.d/
YAML
    mkdir -p .asimov/roadmap
    cat > .asimov/roadmap/engine.yaml << 'YAML'
current:
  id: E1-FASTER
  title: "Parse twice as fast"
  status: in_progress
  deliverables: ["the benchmark shows it"]
backlog:
  - id: E2
  - id: E3
YAML
    printf 'current: {}\nbacklog: []\n' > .asimov/roadmap/docs.yaml
    printf 'current: {}\nbacklog: []\n' > .asimov/roadmap/features.yaml
}

# The system prompt the mock claude was given
_prompt() {
    grep -A1 -x -- '--append-system-prompt' "$ARGS_LOG" | tail -1
}

# ─── Launch ──────────────────────────────────────────────────────────────

@test "a project in lanes is not launched without one, and the lanes are named" {
    _lanes
    run "$ASIMOV_BIN"
    [ "$status" -eq 1 ]
    [[ "$output" == *"This project works in lanes: engine docs features"* ]]
    [[ "$output" == *"asimov --lane <id>"* ]]
    [ ! -f "$ARGS_LOG" ]
}

@test "an unknown lane is refused and the lanes are named" {
    _lanes
    run "$ASIMOV_BIN" --lane nope
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown lane 'nope'. Lanes: engine docs features"* ]]
    [ ! -f "$ARGS_LOG" ]
}

@test "--lane on a project without lanes is refused" {
    run "$ASIMOV_BIN" --lane engine
    [ "$status" -eq 1 ]
    [[ "$output" == *"this project has no lanes"* ]]
    [ ! -f "$ARGS_LOG" ]
}

@test "--lane with no id is refused" {
    run "$ASIMOV_BIN" --lane
    [ "$status" -eq 1 ]
    [[ "$output" == *"--lane needs a lane id"* ]]
}

@test "a lane's launch carries its roadmap's sprint, what it owns and its rule" {
    _lanes
    run "$ASIMOV_BIN" --lane docs
    [ "$status" -eq 0 ]
    local p
    p="$(_prompt)"
    [ "$(jq -r '.lane.id' <<< "$p")" = "docs" ]
    [ "$(jq -r '.lane.title' <<< "$p")" = "Manual" ]
    [ "$(jq -c '.lane.owns' <<< "$p")" = '["docs/","README.md"]' ]
    [ "$(jq -c '.lane.shared' <<< "$p")" = '["changelog.d/",".asimov/roadmap/"]' ]
    [ "$(jq -r '.lane.roadmap' <<< "$p")" = ".asimov/roadmap/docs.yaml" ]
    [ "$(jq -r '.lane.releases' <<< "$p")" = "false" ]
    [ "$(jq -r '[.lane.other_lanes[].id] | join(",")' <<< "$p")" = "engine,features" ]
    local rule
    rule="$(jq -r '.lane.rule' <<< "$p")"
    [[ "$rule" == *'You work in the "docs" lane only'* ]]
    [[ "$rule" == *"add it as an item at the end of that lane's backlog"* ]]
    [[ "$rule" == *"Do not bump the version, release, or edit CHANGELOG.md (the engine lane does); add your change as a new file in changelog.d/"* ]]
    # docs' roadmap has no current sprint, and roadmap.yaml is not read in a lane
    [ "$(jq -r 'has("current_sprint")' <<< "$p")" = "false" ]
}

@test "the releasing lane is told it alone writes the changelog, from the fragments" {
    _lanes
    run "$ASIMOV_BIN" --lane engine
    [ "$status" -eq 0 ]
    local p
    p="$(_prompt)"
    [ "$(jq -r '.lane.releases' <<< "$p")" = "true" ]
    [[ "$(jq -r '.lane.rule' <<< "$p")" == *"You are the lane that releases: only you bump the version and write CHANGELOG.md, from the fragments in changelog.d/"* ]]
    [ "$(jq -c '.current_sprint' <<< "$p")" = '{"id":"E1-FASTER","version":null,"title":"Parse twice as fast","status":"in_progress","deliverables":["the benchmark shows it"]}' ]
}

@test "without changelog fragments the rule names none" {
    _lanes
    yq -i 'del(.changelog)' .asimov/project.yaml
    run "$ASIMOV_BIN" --lane features
    [ "$status" -eq 0 ]
    local rule
    rule="$(_prompt | jq -r '.lane.rule')"
    [[ "$rule" == *"edit CHANGELOG.md (the engine lane does). "* ]]
    [[ "$rule" != *"fragments"* ]]
}

@test "with no releasing lane the rule names none" {
    _lanes
    yq -i 'del(.lanes[0].releases)' .asimov/project.yaml
    run "$ASIMOV_BIN" --lane features
    [ "$status" -eq 0 ]
    [[ "$(_prompt | jq -r '.lane.rule')" == *"edit CHANGELOG.md; add your change"* ]]
}

@test "the launch prints the lane and its sprint, named by id" {
    _lanes
    run "$ASIMOV_BIN" --lane engine
    [ "$status" -eq 0 ]
    [[ "$output" == *"Lane: engine (Engine)"* ]]
    [[ "$output" == *"Sprint: E1-FASTER Parse twice as fast [in_progress], 1 deliverable(s)"* ]]
}

@test "ASIMOV_LANE and --lane=<id> choose the lane as --lane does, and the AI gets ASIMOV_LANE" {
    _lanes
    ASIMOV_LANE=features run "$ASIMOV_BIN"
    [ "$status" -eq 0 ]
    [ "$(_prompt | jq -r '.lane.id')" = "features" ]
    [ "$(cat "$LANE_LOG")" = "features" ]
    rm -f "$ARGS_LOG"
    run "$ASIMOV_BIN" --lane=docs
    [ "$status" -eq 0 ]
    [ "$(_prompt | jq -r '.lane.id')" = "docs" ]
    [ "$(cat "$LANE_LOG")" = "docs" ]
}

@test "lanes that are not valid stop the launch and say why" {
    _lanes
    yq -i '.lanes += [{"id": "docs"}, {"id": "../x"}, {"title": "no id"}, {"id": "two", "releases": true}]' .asimov/project.yaml
    run "$ASIMOV_BIN" --lane engine
    [ "$status" -eq 1 ]
    [[ "$output" == *"lane id 'docs' is used twice"* ]]
    [[ "$output" == *"lane id '../x' must be lowercase letters, digits, - or _"* ]]
    [[ "$output" == *"lane 6 has no id"* ]]
    [[ "$output" == *"2 lanes say releases: true; at most one may"* ]]
    [ ! -f "$ARGS_LOG" ]
}

@test "lanes that are not a list stop the launch" {
    printf 'lanes: engine\n' >> .asimov/project.yaml
    run "$ASIMOV_BIN" --lane engine
    [ "$status" -eq 1 ]
    [[ "$output" == *"'lanes' in project.yaml must be a list"* ]]
}

@test "without lanes the launch reads roadmap.yaml and has no lane" {
    run "$ASIMOV_BIN"
    [ "$status" -eq 0 ]
    [ "$(_prompt | jq -r 'has("lane")')" = "false" ]
    [ "$(_prompt | jq -r '.current_sprint.version')" = "1.0.0" ]
    [ "$(_prompt | jq -r '.current_sprint | has("id")')" = "false" ]
    [[ "$output" != *"Lane:"* ]]
}

# ─── Status ──────────────────────────────────────────────────────────────

@test "status lists each lane's sprint and backlog, and marks this session's" {
    _lanes
    rm .asimov/roadmap/features.yaml
    ASIMOV_LANE=engine run "$ASIMOV_BIN" status
    [[ "$output" == *"lane engine (this session): E1-FASTER Parse twice as fast [in_progress], 2 in backlog"* ]]
    [[ "$output" == *"lane docs:  [], 0 in backlog"* ]]
    [[ "$output" == *"lane features has no .asimov/roadmap/features.yaml (asimov migrate)"* ]]
    [[ "$output" != *"roadmap: 1.0.0"* ]]
}

@test "status names lanes that are not valid" {
    _lanes
    yq -i '.lanes += [{"id": "docs"}]' .asimov/project.yaml
    run "$ASIMOV_BIN" status
    [[ "$output" == *"lanes: lane id 'docs' is used twice"* ]]
}

# ─── Migrate ─────────────────────────────────────────────────────────────

@test "migrate gives each lane a roadmap, keeps roadmap/ and names a file of no lane" {
    _lanes
    rm .asimov/roadmap/docs.yaml
    printf 'x: 1\n' > .asimov/roadmap/stray.yaml
    run "$ASIMOV_BIN" migrate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Added .asimov/roadmap/docs.yaml"* ]]
    [ "$(yq -o=json -I=0 '.' .asimov/roadmap/docs.yaml)" = '{"current":{},"backlog":[]}' ]
    [[ "$output" == *".asimov/roadmap/stray.yaml (no lane of that name)"* ]]
    [[ "$output" != *"  .asimov/roadmap
"* ]]
    rm .asimov/roadmap/stray.yaml
    run "$ASIMOV_BIN" migrate
    [[ "$output" == *"Already up to date."* ]]
}

@test "migrate says what is wrong with lanes and writes no roadmap" {
    _lanes
    rm -r .asimov/roadmap
    yq -i '.lanes += [{"id": "Bad"}]' .asimov/project.yaml
    run "$ASIMOV_BIN" migrate
    [[ "$output" == *"Lanes in project.yaml need fixing by hand:"* ]]
    [[ "$output" == *"lane id 'Bad' must be"* ]]
    [ ! -d .asimov/roadmap ]
}

@test "without lanes migrate still calls roadmap/ unexpected" {
    mkdir -p .asimov/roadmap
    run "$ASIMOV_BIN" migrate
    [[ "$output" == *"Unexpected files in .asimov/"*".asimov/roadmap"* ]]
}

# ─── Pre-commit hook ─────────────────────────────────────────────────────

_hook_repo() {
    export GIT_CEILING_DIRECTORIES="$TEST_TMPDIR"
    export TMPDIR="${TEST_TMPDIR}/tmp"
    mkdir -p "$TMPDIR"
    _lanes
    git init -q
    mkdir -p docs src changelog.d
    printf 'a\n' > docs/guide.txt
    printf 'b\n' > src/main.txt
    printf 'c\n' > changelog.d/1.txt
    printf 'd\n' > README.md.txt
    git add docs/guide.txt changelog.d/1.txt .asimov/roadmap/engine.yaml .asimov/project.yaml
}

@test "the hook names staged files outside the lane, and still passes" {
    _hook_repo
    git add src/main.txt README.md.txt
    ASIMOV_LANE=docs run "${PROJECT_ROOT}/hooks/pre-commit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LANE docs: these staged files are outside what the lane owns:"* ]]
    [[ "$output" == *"   src/main.txt"* ]]
    [[ "$output" == *"   README.md.txt"* ]]
    [[ "$output" == *"   .asimov/project.yaml"* ]]
    # owned, shared, and another lane's roadmap are not named
    [[ "$output" != *"docs/guide.txt"* ]]
    [[ "$output" != *"changelog.d/1.txt"* ]]
    [[ "$output" != *"roadmap/engine.yaml"* ]]
    [[ "$output" == *"ALL QUALITY GATES PASSED"* ]]
}

@test "the hook says nothing about lanes when every file is the lane's" {
    _hook_repo
    git rm -q --cached .asimov/project.yaml
    ASIMOV_LANE=docs run "${PROJECT_ROOT}/hooks/pre-commit"
    [ "$status" -eq 0 ]
    [[ "$output" != *"LANE"* ]]
}

@test "the hook checks no lane without ASIMOV_LANE, or for a lane that is not there" {
    _hook_repo
    git add src/main.txt
    run "${PROJECT_ROOT}/hooks/pre-commit"
    [ "$status" -eq 0 ]
    [[ "$output" != *"LANE"* ]]
    ASIMOV_LANE=nope run "${PROJECT_ROOT}/hooks/pre-commit"
    [ "$status" -eq 0 ]
    [[ "$output" != *"LANE"* ]]
}

@test "the hook does not read a lane id that is not one" {
    _hook_repo
    ASIMOV_LANE='x") | .id, ("' run "${PROJECT_ROOT}/hooks/pre-commit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"is not a lane id; not checked"* ]]
}

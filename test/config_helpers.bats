#!/usr/bin/env bats

load test_helper

setup() {
    setup_tmpdir
    source_asimov_functions
}

teardown() {
    teardown_tmpdir
}

# ─── cfg_get ─────────────────────────────────────────────────────────────

@test "cfg_get returns value for existing key" {
    cat > "${TEST_TMPDIR}/test.yaml" << 'YAML'
foo:
  bar: hello
YAML
    run cfg_get "${TEST_TMPDIR}/test.yaml" '.foo.bar'
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "cfg_get returns empty for missing key" {
    cat > "${TEST_TMPDIR}/test.yaml" << 'YAML'
foo:
  bar: hello
YAML
    run cfg_get "${TEST_TMPDIR}/test.yaml" '.foo.missing'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "cfg_get returns 0 for missing file" {
    run cfg_get "${TEST_TMPDIR}/nonexistent.yaml" '.foo'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "cfg_get handles null value" {
    cat > "${TEST_TMPDIR}/test.yaml" << 'YAML'
foo:
  bar: null
YAML
    run cfg_get "${TEST_TMPDIR}/test.yaml" '.foo.bar'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "cfg_get handles nested paths" {
    cat > "${TEST_TMPDIR}/test.yaml" << 'YAML'
launch:
  claude:
    model: opus
YAML
    run cfg_get "${TEST_TMPDIR}/test.yaml" '.launch.claude.model'
    [ "$status" -eq 0 ]
    [ "$output" = "opus" ]
}

# ─── cfg_list ────────────────────────────────────────────────────────────

@test "cfg_list returns list items as lines" {
    cat > "${TEST_TMPDIR}/test.yaml" << 'YAML'
launch:
  claude:
    args:
      - --flag-one
      - --flag-two
YAML
    run cfg_list "${TEST_TMPDIR}/test.yaml" '.launch.claude.args'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "--flag-one" ]
    [ "${lines[1]}" = "--flag-two" ]
}

@test "cfg_list returns empty for missing key" {
    cat > "${TEST_TMPDIR}/test.yaml" << 'YAML'
foo: bar
YAML
    run cfg_list "${TEST_TMPDIR}/test.yaml" '.launch.claude.args'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "cfg_list returns 0 for missing file" {
    run cfg_list "${TEST_TMPDIR}/nonexistent.yaml" '.foo'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "cfg_list handles empty array" {
    cat > "${TEST_TMPDIR}/test.yaml" << 'YAML'
items: []
YAML
    run cfg_list "${TEST_TMPDIR}/test.yaml" '.items'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# ─── cfg_env ─────────────────────────────────────────────────────────────

@test "cfg_env returns KEY=VALUE lines" {
    cat > "${TEST_TMPDIR}/test.yaml" << 'YAML'
launch:
  claude:
    env:
      FOO: "bar"
      BAZ: "qux"
YAML
    run cfg_env "${TEST_TMPDIR}/test.yaml" '.launch.claude.env'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "FOO=bar" ]
    [ "${lines[1]}" = "BAZ=qux" ]
}

@test "cfg_env returns empty for missing key" {
    cat > "${TEST_TMPDIR}/test.yaml" << 'YAML'
foo: bar
YAML
    run cfg_env "${TEST_TMPDIR}/test.yaml" '.launch.claude.env'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "cfg_env returns 0 for missing file" {
    run cfg_env "${TEST_TMPDIR}/nonexistent.yaml" '.foo'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "cfg_env handles empty map" {
    cat > "${TEST_TMPDIR}/test.yaml" << 'YAML'
env: {}
YAML
    run cfg_env "${TEST_TMPDIR}/test.yaml" '.env'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

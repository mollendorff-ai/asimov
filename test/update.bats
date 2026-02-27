#!/usr/bin/env bats

load test_helper

setup() {
    setup_tmpdir

    # Create a writable copy of the asimov binary for update to replace
    ASIMOV_COPY="${TEST_TMPDIR}/bin/asimov"
    mkdir -p "${TEST_TMPDIR}/bin"
    cp "$ASIMOV_BIN" "$ASIMOV_COPY"
    chmod +x "$ASIMOV_COPY"

    # Set ASIMOV_DATA to a temp location with protocols/ and hooks/ dirs
    export ASIMOV_DATA="${TEST_TMPDIR}/data"
    mkdir -p "${ASIMOV_DATA}/protocols" "${ASIMOV_DATA}/hooks"

    # Mock bin directory
    MOCK_DIR="${TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="${MOCK_DIR}:${PATH}"
}

teardown() {
    teardown_tmpdir
}

# Create a curl mock that returns a fake asimov script with the given version
mock_curl_version() {
    local version="$1"
    cat > "${MOCK_DIR}/curl" << CURL_EOF
#!/usr/bin/env bash
# Detect -o flag for file downloads
output=""
args=("\$@")
for ((i=0; i<\${#args[@]}; i++)); do
    if [[ "\${args[i]}" == "-o" ]]; then
        output="\${args[i+1]}"
        break
    fi
done

# Last positional arg is the URL
url="\${args[-1]}"

if [[ "\$url" == */bin/asimov ]]; then
    # Return a fake asimov script with the requested version
    echo 'ASIMOV_VERSION="${version}"'
    echo '# fake asimov binary'
elif [[ -n "\$output" ]]; then
    # Protocol/hook download -- create the file
    touch "\$output"
else
    exit 1
fi
CURL_EOF
    chmod +x "${MOCK_DIR}/curl"
}

# Create a curl mock that always fails
mock_curl_fail() {
    cat > "${MOCK_DIR}/curl" << 'CURL_EOF'
#!/usr/bin/env bash
exit 1
CURL_EOF
    chmod +x "${MOCK_DIR}/curl"
}

# Create a curl mock that returns content with no ASIMOV_VERSION line
mock_curl_no_version() {
    cat > "${MOCK_DIR}/curl" << 'CURL_EOF'
#!/usr/bin/env bash
# Return content with no parseable version
echo '# no version here'
echo 'echo hello'
CURL_EOF
    chmod +x "${MOCK_DIR}/curl"
}

# ─── Already up to date ─────────────────────────────────────────────────

@test "update prints 'Already up to date' when versions match" {
    mock_curl_version "2.11.0"
    run "$ASIMOV_COPY" update
    [[ "$output" == *"Already up to date. (v2.11.0)"* ]]
}

@test "update exits 0 when versions match" {
    mock_curl_version "2.11.0"
    run "$ASIMOV_COPY" update
    [ "$status" -eq 0 ]
}

# ─── Upgrade path ────────────────────────────────────────────────────────

@test "update replaces binary when newer version available" {
    local before
    before="$(cat "$ASIMOV_COPY")"
    mock_curl_version "2.12.0"
    run "$ASIMOV_COPY" update
    [ "$status" -eq 0 ]
    local after
    after="$(cat "$ASIMOV_COPY")"
    [ "$before" != "$after" ]
}

@test "update downloads all 4 protocol files when upgrade needed" {
    mock_curl_version "2.12.0"
    run "$ASIMOV_COPY" update
    [ "$status" -eq 0 ]
    [ -f "${ASIMOV_DATA}/protocols/freshness.json" ]
    [ -f "${ASIMOV_DATA}/protocols/sycophancy.json" ]
    [ -f "${ASIMOV_DATA}/protocols/sprint.json" ]
    [ -f "${ASIMOV_DATA}/protocols/coding-standards.json" ]
}

@test "update downloads pre-commit hook when upgrade needed" {
    mock_curl_version "2.12.0"
    run "$ASIMOV_COPY" update
    [ "$status" -eq 0 ]
    [ -f "${ASIMOV_DATA}/hooks/pre-commit" ]
}

@test "update hook is executable after update" {
    mock_curl_version "2.12.0"
    run "$ASIMOV_COPY" update
    [ "$status" -eq 0 ]
    [ -x "${ASIMOV_DATA}/hooks/pre-commit" ]
}

@test "update prints transition message vOLD → vNEW" {
    mock_curl_version "2.12.0"
    run "$ASIMOV_COPY" update
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updating asimov v2.11.0 → v2.12.0"* ]]
    [[ "$output" == *"Updated to v2.12.0."* ]]
}

# ─── Error paths ─────────────────────────────────────────────────────────

@test "update exits 1 if curl fails to fetch binary" {
    mock_curl_fail
    run "$ASIMOV_COPY" update
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed to fetch latest release"* ]]
}

@test "update exits 1 if version cannot be parsed from response" {
    mock_curl_no_version
    run "$ASIMOV_COPY" update
    [ "$status" -ne 0 ]
}

# ─── Dispatcher ──────────────────────────────────────────────────────────

@test "update command is recognized by asimov dispatcher" {
    mock_curl_version "2.11.0"
    run "$ASIMOV_COPY" update
    [ "$status" -eq 0 ]
    # Should NOT get "Unknown command" error
    [[ "$output" != *"Unknown command"* ]]
}

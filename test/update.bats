#!/usr/bin/env bats

load test_helper

setup() {
    setup_tmpdir

    # Writable copy of the asimov binary for update to replace
    ASIMOV_COPY="${TEST_TMPDIR}/bin/asimov"
    mkdir -p "${TEST_TMPDIR}/bin"
    cp "$ASIMOV_BIN" "$ASIMOV_COPY"
    chmod +x "$ASIMOV_COPY"
    CURRENT_VERSION="$(grep '^ASIMOV_VERSION=' "$ASIMOV_BIN" | cut -d'"' -f2)"

    # Installed data dir that update writes into
    export ASIMOV_DATA="${TEST_TMPDIR}/data"
    mkdir -p "${ASIMOV_DATA}/protocols" "${ASIMOV_DATA}/hooks"

    MOCK_DIR="${TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="${MOCK_DIR}:${PATH}"

    # Fake release tree served by the curl mock
    RELEASE_DIR="${TEST_TMPDIR}/release"
}

teardown() {
    teardown_tmpdir
}

# Build a fake release for the given version, with a matching SHA256SUMS
make_release() {
    local version="$1"
    mkdir -p "${RELEASE_DIR}/bin" "${RELEASE_DIR}/hooks" "${RELEASE_DIR}/protocols"
    printf 'ASIMOV_VERSION="%s"\n# fake asimov binary\n' "$version" > "${RELEASE_DIR}/bin/asimov"
    echo '#!/bin/bash' > "${RELEASE_DIR}/hooks/pre-commit"
    for f in freshness.json sycophancy.json sprint.json coding-standards.json; do
        echo "{\"rule\": \"${f} v${version}\"}" > "${RELEASE_DIR}/protocols/${f}"
    done
    local sha="sha256sum"
    command -v sha256sum &>/dev/null || sha="shasum -a 256"
    (cd "$RELEASE_DIR" && $sha bin/asimov hooks/pre-commit protocols/*.json > SHA256SUMS)
    echo "v${version}" > "${RELEASE_DIR}/TAG"
}

# curl mock: latest-release API, SHA256SUMS asset and raw files at the tag
mock_curl_release() {
    cat > "${MOCK_DIR}/curl" << CURL_EOF
#!/usr/bin/env bash
output=""
args=("\$@")
for ((i=0; i<\${#args[@]}; i++)); do
    [[ "\${args[i]}" == "-o" ]] && output="\${args[i+1]}"
    [[ "\${args[i]}" == http* ]] && url="\${args[i]}"
done
tag="\$(cat "${RELEASE_DIR}/TAG")"
case "\$url" in
    */releases/latest) echo "{\"tag_name\": \"\${tag}\"}" ;;
    */releases/download/*/SHA256SUMS) cp "${RELEASE_DIR}/SHA256SUMS" "\$output" ;;
    */\${tag}/*) cp "${RELEASE_DIR}/\${url##*/\${tag}/}" "\$output" ;;
    *) exit 1 ;;
esac
CURL_EOF
    chmod +x "${MOCK_DIR}/curl"
}

mock_curl_fail() {
    printf '#!/usr/bin/env bash\nexit 1\n' > "${MOCK_DIR}/curl"
    chmod +x "${MOCK_DIR}/curl"
}

# ─── Already up to date ─────────────────────────────────────────────────

@test "update prints 'Already up to date' when latest tag matches" {
    make_release "$CURRENT_VERSION"
    mock_curl_release
    run "$ASIMOV_COPY" update
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already up to date. (v${CURRENT_VERSION})"* ]]
}

# ─── Upgrade path ────────────────────────────────────────────────────────

@test "update replaces binary with the tagged release" {
    make_release "99.0.0"
    mock_curl_release
    run "$ASIMOV_COPY" update
    [ "$status" -eq 0 ]
    grep -q 'ASIMOV_VERSION="99.0.0"' "$ASIMOV_COPY"
    [ -x "$ASIMOV_COPY" ]
}

@test "update installs all 4 protocols and the hook" {
    make_release "99.0.0"
    mock_curl_release
    run "$ASIMOV_COPY" update
    [ "$status" -eq 0 ]
    for f in freshness.json sycophancy.json sprint.json coding-standards.json; do
        grep -q "v99.0.0" "${ASIMOV_DATA}/protocols/${f}"
    done
    [ -x "${ASIMOV_DATA}/hooks/pre-commit" ]
}

@test "update prints transition message and migrate reminder" {
    make_release "99.0.0"
    mock_curl_release
    run "$ASIMOV_COPY" update
    [[ "$output" == *"Updating asimov v${CURRENT_VERSION} → v99.0.0"* ]]
    [[ "$output" == *"Updated to v99.0.0."* ]]
    [[ "$output" == *"asimov migrate"* ]]
}

# ─── Verification ────────────────────────────────────────────────────────

@test "update refuses a file whose checksum does not match" {
    make_release "99.0.0"
    echo "tampered" >> "${RELEASE_DIR}/hooks/pre-commit"
    mock_curl_release
    local before; before="$(cat "$ASIMOV_COPY")"
    run "$ASIMOV_COPY" update
    [ "$status" -eq 1 ]
    [[ "$output" == *"checksum mismatch for hooks/pre-commit"* ]]
    [ "$(cat "$ASIMOV_COPY")" = "$before" ]
    [ ! -f "${ASIMOV_DATA}/hooks/pre-commit" ]
}

@test "update refuses a file missing from SHA256SUMS" {
    make_release "99.0.0"
    grep -v 'sprint.json' "${RELEASE_DIR}/SHA256SUMS" > "${RELEASE_DIR}/S" && mv "${RELEASE_DIR}/S" "${RELEASE_DIR}/SHA256SUMS"
    mock_curl_release
    run "$ASIMOV_COPY" update
    [ "$status" -eq 1 ]
    [[ "$output" == *"checksum mismatch for protocols/sprint.json"* ]]
}

# ─── Error paths ─────────────────────────────────────────────────────────

@test "update exits 1 if the latest release cannot be fetched" {
    mock_curl_fail
    run "$ASIMOV_COPY" update
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed to fetch latest release"* ]]
}

@test "update command is recognized by asimov dispatcher" {
    make_release "$CURRENT_VERSION"
    mock_curl_release
    run "$ASIMOV_COPY" update
    [[ "$output" != *"Unknown command"* ]]
}

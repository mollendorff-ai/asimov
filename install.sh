#!/usr/bin/env bash
# Asimov installer — curl -fsSL https://raw.githubusercontent.com/mollendorff-ai/asimov/main/install.sh | bash
# Installs the latest tagged release and verifies every file against its SHA256SUMS.
set -euo pipefail

REPO="mollendorff-ai/asimov"
PREFIX="${HOME}/.local"
BINDIR="${PREFIX}/bin"
DATADIR="${PREFIX}/share/asimov"
PROTOCOLS=(freshness.json sycophancy.json sprint.json coding-standards.json)
FILES=(bin/asimov hooks/pre-commit)
for f in "${PROTOCOLS[@]}"; do FILES+=("protocols/${f}"); done

sha256_of() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

echo "Installing asimov..."

tag="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)" || tag=""
if [ -z "$tag" ]; then
    echo "Could not find a release of ${REPO}." >&2
    exit 1
fi
echo "Latest release: ${tag}"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
curl -fsSL "https://github.com/${REPO}/releases/download/${tag}/SHA256SUMS" -o "${stage}/SHA256SUMS"
for f in "${FILES[@]}"; do
    mkdir -p "${stage}/$(dirname "$f")"
    curl -fsSL "https://raw.githubusercontent.com/${REPO}/${tag}/${f}" -o "${stage}/${f}"
    expected="$(awk -v p="$f" '$2 == p {print $1}' "${stage}/SHA256SUMS")"
    if [ -z "$expected" ] || [ "$expected" != "$(sha256_of "${stage}/${f}")" ]; then
        echo "Checksum mismatch for ${f}; nothing was installed." >&2
        exit 1
    fi
done

mkdir -p "$BINDIR" "${DATADIR}/protocols" "${DATADIR}/hooks"
cp "${stage}/bin/asimov" "${BINDIR}/asimov"
chmod +x "${BINDIR}/asimov"
for f in "${PROTOCOLS[@]}"; do
    cp "${stage}/protocols/${f}" "${DATADIR}/protocols/${f}"
done
cp "${stage}/hooks/pre-commit" "${DATADIR}/hooks/pre-commit"
chmod +x "${DATADIR}/hooks/pre-commit"

echo ""
echo "Installed asimov ${tag} to ${BINDIR}/asimov"
echo "Data files in ${DATADIR}/"
echo ""

# Check dependencies
if ! command -v jq &>/dev/null; then
    echo "Missing dependency: jq  (brew install jq  # or: apt install jq)"
fi
if ! command -v yq &>/dev/null; then
    echo "Missing dependency: yq  (brew install yq  # or: go install github.com/mikefarah/yq/v4@latest)"
elif ! yq --version 2>&1 | grep -qi mikefarah; then
    echo "Wrong yq: asimov needs mikefarah/yq v4 (the Go version), not the Python one from apt."
    echo "  Download: https://github.com/mikefarah/yq/releases"
fi

if echo "$PATH" | tr ':' '\n' | grep -qx "$BINDIR"; then
    echo "Run 'asimov --version' to verify."
else
    echo "Add ${BINDIR} to your PATH:"
    echo "  export PATH=\"${BINDIR}:\$PATH\""
fi

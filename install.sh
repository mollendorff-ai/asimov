#!/usr/bin/env bash
# Asimov installer — curl -fsSL https://raw.githubusercontent.com/mollendorff-ai/asimov/main/install.sh | bash
set -euo pipefail

REPO="https://raw.githubusercontent.com/mollendorff-ai/asimov/main"
PREFIX="${HOME}/.local"
BINDIR="${PREFIX}/bin"
DATADIR="${PREFIX}/share/asimov"

echo "Installing asimov..."

mkdir -p "$BINDIR" "${DATADIR}/protocols" "${DATADIR}/hooks"

curl -fsSL "${REPO}/bin/asimov" -o "${BINDIR}/asimov"
chmod +x "${BINDIR}/asimov"

for f in freshness.json sycophancy.json sprint.json coding-standards.json; do
    curl -fsSL "${REPO}/protocols/${f}" -o "${DATADIR}/protocols/${f}"
done

curl -fsSL "${REPO}/hooks/pre-commit" -o "${DATADIR}/hooks/pre-commit"
chmod +x "${DATADIR}/hooks/pre-commit"

echo ""
echo "Installed asimov to ${BINDIR}/asimov"
echo "Data files in ${DATADIR}/"
echo ""

# Check dependencies
missing=()
command -v yq &>/dev/null || missing+=("yq")
command -v jq &>/dev/null || missing+=("jq")
if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing dependencies: ${missing[*]}"
    echo "Install:"
    for dep in "${missing[@]}"; do
        case "$dep" in
            yq) echo "  brew install yq  # or: go install github.com/mikefarah/yq/v4@latest" ;;
            jq) echo "  brew install jq   # or: apt install jq" ;;
        esac
    done
    echo ""
fi

if echo "$PATH" | tr ':' '\n' | grep -qx "$BINDIR"; then
    echo "Run 'asimov --version' to verify."
else
    echo "Add ${BINDIR} to your PATH:"
    echo "  export PATH=\"${BINDIR}:\$PATH\""
fi

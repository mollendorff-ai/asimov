# Contributing

Thanks for your interest in Asimov.

## Development setup

```bash
git clone https://github.com/mollendorff-ai/asimov.git
cd asimov
brew install yq jq shellcheck bats-core  # macOS (yq must be mikefarah/yq v4)
```

## Running checks

```bash
make lint    # shellcheck on bin/asimov, hooks/pre-commit, install.sh
make test    # bats test suite
```

Both must pass before submitting a PR.

## Project structure

```text
bin/asimov           # main CLI (~1,550 lines bash)
hooks/pre-commit     # quality gate (~370 lines bash)
protocols/*.json     # behavioral protocols (4 files)
test/*.bats          # bats test suite
.asimov/             # project's own asimov config
```

## Pull requests

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Run `make lint && make test`
4. Open a PR with a clear description of what changed and why

Keep PRs focused -- one feature or fix per PR.

## Adding a protocol

Protocols are plain JSON files in `protocols/`. Each must have
a `rule` field (a single string given to the AI at launch).
Add the file name to `ASIMOV_PROTOCOLS` in `bin/asimov` and `PROTOCOLS` in
`install.sh`, and add its `rule` to `build_system_prompt`.

## Adding a language to the pre-commit hook

Follow the existing pattern in `hooks/pre-commit`:

1. Detect via a marker file (e.g., `Cargo.toml` for Rust)
2. Run format, lint, and coverage checks
3. Provide clear error messages with remediation commands
4. Add a corresponding test in `test/pre_commit.bats`

## Code style

- Bash with `set -euo pipefail`
- Quote all variables
- Use `command -v` to check tool availability
- Keep functions focused and well-named
- No commented-out code

## Releasing

Bump `ASIMOV_VERSION` in `bin/asimov` and add a `## X.Y.Z` section to
CHANGELOG.md. When that lands on `main` and CI passes, the `release` job
tags `vX.Y.Z` and publishes the release with `SHA256SUMS`.

# Contributing

Thanks for your interest in Asimov.

## Development setup

```bash
git clone https://github.com/mollendorff-ai/asimov.git
cd asimov
brew install yq jq shellcheck bats-core  # macOS
```

## Running checks

```bash
make lint    # shellcheck on bin/asimov and hooks/pre-commit
make test    # bats test suite
```

Both must pass before submitting a PR.

## Project structure

```text
bin/asimov           # main CLI (~500 lines bash)
hooks/pre-commit     # quality gate (~360 lines bash)
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
a `rule` field (a single string injected into the system prompt).
Add the new file to the copy loops in `cmd_init`, `cmd_migrate`,
`launch_ai`, and `build_system_prompt`.

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

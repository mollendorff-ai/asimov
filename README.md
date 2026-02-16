# Asimov

AI coding assistants (Claude Code, Gemini CLI, Codex CLI) launch
with no memory of your project's conventions. Every session starts
cold: the AI doesn't know your stack, your quality bar, or what
sprint you're on.

Asimov fixes that. It injects behavioral protocols into the system
prompt and warms up each session with your roadmap -- so the AI
starts aligned, not blank.

## What it does

- **Protocols** -- JSON rules injected into the system prompt at
  launch. They survive context compaction and steer behavior across
  the entire session (freshness, sycophancy, coding standards,
  autonomous sprints).
- **Quality gate** -- a pre-commit hook that auto-detects your
  language and enforces format + lint + 100% coverage at commit
  time. Works for Rust, Python, Node, Go, and Flutter.
- **Session warmup** -- reads your roadmap before the interactive
  session so the AI knows what you're working on.
- **Vendor-neutral** -- one config works with Claude Code, Gemini
  CLI, and Codex CLI.

## Install

```bash
git clone https://github.com/mollendorff-ai/asimov.git
cd asimov
make install
```

Copies to `~/.local/bin/` and `~/.local/share/asimov/`.
Requires `yq` and `jq` (`brew install yq jq`).

## Quick start

```bash
cd your-project
asimov init        # scaffold .asimov/, install pre-commit hook
asimov             # launch AI with protocols + roadmap warmup
```

`asimov init` creates:

```text
.asimov/
├── project.yaml          # identity, description, stack, conventions
├── roadmap.yaml          # milestones + sprint status
├── freshness.json        # protocol: use ref fetch for web content
├── sycophancy.json       # protocol: truth over comfort
├── sprint.json           # protocol: autonomous mode triggers
└── coding-standards.json # protocol: code quality principles
.git/hooks/pre-commit     # quality gate (format + lint + coverage)
```

## Config

Global defaults in `~/.asimov/config.yaml`
(auto-created on first run):

```yaml
launch:
  default_ai: claude

  claude:
    model: opus
    args:
      - --dangerously-skip-permissions
    env:
      MAX_THINKING_TOKENS: "1000000"

  gemini:
    args:
      - --yolo

  codex:
    args:
      - --full-auto
```

Per-project overrides go in `.asimov/launch.yaml`
(same format, project wins on conflicts).

## Protocols

Injected into the AI system prompt at launch. They persist
through context compaction -- the AI never forgets them.

| Protocol | Purpose |
| -------- | ------- |
| `freshness.json` | Use `ref fetch` for web content |
| `sycophancy.json` | Prioritize accuracy over comfort |
| `sprint.json` | Autonomous mode until deliverables done |
| `coding-standards.json` | Readable code, tests as docs, zero warnings |

## Quality gate

The pre-commit hook auto-detects your project language:

| Language | Format | Lint | Coverage |
| -------- | ------ | ---- | -------- |
| Rust | `cargo fmt` | `clippy --pedantic` | `llvm-cov 100%` |
| Python | `ruff fmt` | `ruff --select ALL` | `pytest-cov 100%` |
| Node | `prettier` | `eslint --max-warn=0` | `npm test` |
| Go | `gofumpt` | `golangci-lint` | `go-test-cov 100%` |
| Flutter | `dart format` | `dart analyze` | `flutter test 100%` |

The hook includes a warning to LLM agents: bypassing it is
prohibited. If checks fail, the AI must fix the code.

## Development

```bash
make lint    # shellcheck on all shell scripts
make test    # bats test suite (78 tests)
```

## License

[MIT](LICENSE)

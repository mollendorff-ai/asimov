# Asimov

Launches AI coding assistants with behavioral protocols
and a pre-commit quality gate.
Works with Claude Code, Gemini CLI, and Codex CLI.

## Install

```bash
make install
```

Copies to `~/.local/bin/` and `~/.local/share/asimov/`.

## Setup

```bash
cd your-project
asimov init
```

Creates:

```text
.asimov/
├── project.yaml    # project identity
├── roadmap.yaml    # milestones + sprint status
├── freshness.json  # protocol: use ref fetch
├── sycophancy.json # protocol: truth over comfort
└── sprint.json     # protocol: autonomous mode
.git/hooks/pre-commit
```

## Usage

```bash
asimov          # launch AI with protocols + roadmap warmup
asimov init     # scaffold .asimov/ in current project
asimov --help
```

Running `asimov` with no arguments:

1. Injects protocols into the system prompt
   (never compacted, always active)
2. Runs a warmup that reads the roadmap
   (forces the AI to load sprint context)
3. Starts an interactive session

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

## Pre-commit hook

Auto-detects project language and runs:

| Language | Format        | Lint                  | Coverage            |
| -------- | ------------- | --------------------- | ------------------- |
| Rust     | `cargo fmt`   | `clippy --pedantic`   | `llvm-cov 100%`     |
| Python   | `ruff fmt`    | `ruff --select ALL`   | `pytest-cov 100%`   |
| Node     | `prettier`    | `eslint --max-warn=0` | `npm test`          |
| Go       | `gofumpt`     | `golangci-lint`       | `go-test-cov 100%`  |
| Flutter  | `dart format` | `dart analyze`        | `flutter test 100%` |

The hook tells the AI exactly what failed and how
to fix it. Quality is enforced at commit time,
not via protocols.

## Protocols

Injected into the AI system prompt at launch
(never lost during context compaction):

- **freshness.json** -- use `ref fetch <url>` for
  web content (bypasses bot protection)
- **sycophancy.json** -- prioritize accuracy over
  comfort, disagree when appropriate
- **sprint.json** -- when roadmap status is
  `autonomous`, work until deliverables are done

## License

[MIT](LICENSE)

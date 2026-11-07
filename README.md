# Asimov

[![CI](https://github.com/mollendorff-ai/asimov/actions/workflows/ci.yml/badge.svg)](https://github.com/mollendorff-ai/asimov/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/lctavares/c99beaff02a1895916d78b8d2a8ad79d/raw/tests.json)](https://github.com/mollendorff-ai/asimov/actions/workflows/ci.yml)

**Run AI coding CLIs in full-autonomy mode, and still get good code.**

> **Read this first.** Asimov is a personal tool. It launches Claude Code,
> Gemini CLI or Codex CLI with every approval prompt turned off, on purpose,
> so the agent can write, run and commit code in the terminal with as little
> human interaction as possible. Use it only in a sandbox (a VM, container or
> throwaway machine) where an agent with unrestricted shell access cannot hurt
> anything you care about. It is published because there is no reason not to,
> not because it is looking for users. Built with heavy AI assistance.

Status: personal, works for its author, no stability promises.

## The idea

Autonomy without guardrails produces fast garbage. Asimov pairs the two:

- **Full autonomy** -- the agent runs with no permission prompts, at the
  highest model and effort settings.
- **Behavioral protocols** -- short JSON rules (honesty over comfort, coding
  standards, autonomous sprint lifecycle, web fetching) given to the agent at
  launch.
- **Session warmup** -- the agent reads your roadmap before you type anything,
  so it starts on the current sprint.
- **Quality gate** -- a pre-commit hook that blocks any commit that is not
  formatted, lint-clean and 100% covered. The agent cannot ship unchecked
  code; it has to fix it.

## Install

```bash
ASIMOV=https://raw.githubusercontent.com
curl -fsSL $ASIMOV/mollendorff-ai/asimov/main/install.sh | bash
```

The installer downloads the latest tagged release and checks every file
against the release's `SHA256SUMS` before installing anything. Or from a
clone:

```bash
git clone https://github.com/mollendorff-ai/asimov.git
cd asimov
make install
```

Installs to `~/.local/bin/` and `~/.local/share/asimov/`.

**Requires `jq` and mikefarah's `yq` v4** (the Go version):
`brew install yq jq`. On Debian and Ubuntu, `apt install yq` gives a
different, Python-based `yq` that does not work; download mikefarah's from
its [releases page](https://github.com/mikefarah/yq/releases). Asimov
checks and tells you if the wrong one is installed.

## Quick start

```bash
cd your-project
asimov init        # scaffold .asimov/, install pre-commit hook
asimov             # launch the AI with protocols + roadmap warmup
asimov migrate     # bring an older .asimov/ up to date
asimov update      # install the latest tagged release
```

`asimov init` creates:

```text
.asimov/
├── project.yaml          # identity, description, stack, conventions
├── roadmap.yaml          # current milestone + backlog
├── freshness.json        # protocol: prefer ref fetch for web pages
├── sycophancy.json       # protocol: truth over comfort
├── sprint.json           # protocol: autonomous mode lifecycle
└── coding-standards.json # protocol: code quality principles
.git/hooks/pre-commit     # quality gate (format + lint + coverage)
```

## How each AI gets the protocols

- **Claude Code** -- protocols via `--append-system-prompt` (system
  prompt, outside the compacted transcript); roadmap warmup as a separate
  `-p` turn, then `--continue`; autonomy via
  `--dangerously-skip-permissions`.
- **Gemini CLI** -- protocols and warmup in the first message via
  `--prompt-interactive`; autonomy via `--approval-mode=yolo`.
- **Codex CLI** -- protocols and warmup in the first message (initial
  prompt); autonomy via `--full-auto`.

Claude Code is the primary target. Gemini CLI and Codex CLI have no flag to
append to the system prompt, so their protocols arrive as the first message
and can be lost when a long session is compacted.

## Config

Global defaults in `~/.asimov/config.yaml` (created on first run):

```yaml
launch:
  default_ai: claude

  claude:
    model: opus
    args:
      - --dangerously-skip-permissions
    env:
      MAX_THINKING_TOKENS: "1000000"
      CLAUDE_CODE_EFFORT_LEVEL: "max"
      CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"

  gemini:
    args:
      - --approval-mode=yolo

  codex:
    args:
      - --full-auto
```

Per-project overrides go in `.asimov/launch.yaml`, same format. For each
setting (`model`, `args`, `env`), a project value replaces the global one
entirely; lists and maps are not merged.

### Why these defaults

Everything is set for maximum autonomy and maximum reasoning, because that
is the point of the tool:

- `--dangerously-skip-permissions` -- no tool-approval prompts ([docs][cc-perms])
- `MAX_THINKING_TOKENS` -- large extended-thinking budget ([docs][cc-think])
- `CLAUDE_CODE_EFFORT_LEVEL: max` -- deepest reasoning ([docs][cc-settings])
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: 1` -- multi-agent coordination ([docs][cc-teams])
- `--approval-mode=yolo` -- Gemini CLI auto-approves all actions ([docs][gem-cli])
- `--full-auto` -- Codex CLI autonomous mode ([docs][codex-cli])

The cost is real: every Claude launch spends one extra warmup turn on the
largest model at maximum effort. And again: an agent with these flags can
run any command your user can. Sandbox only.

## Protocols

| Protocol | Purpose |
| -------- | ------- |
| `freshness.json` | Prefer `ref fetch` for web pages when [ref][ref] is installed |
| `sycophancy.json` | Accuracy over comfort |
| `sprint.json` | Status `autonomous`: work until deliverables are done |
| `coding-standards.json` | Readable code, tests as docs, zero warnings |

## Quality gate

The pre-commit hook detects the project language by marker file. For
Node, coverage is only enforced if your test config sets a 100% threshold.

| Language | Format | Lint | Coverage |
| -------- | ------ | ---- | -------- |
| Rust | `cargo fmt` | `clippy --pedantic` | `llvm-cov` 100% |
| Python | `ruff format` | project config, else `ALL` | `pytest-cov` 100% |
| Node | `prettier` | `eslint --max-warnings=0` | `npm test` |
| Go | `gofumpt` | `golangci-lint` | `go-test-coverage` 100% |
| Flutter | `dart format` | `dart analyze` | `flutter test` 100% |

The hook carries a notice telling AI agents not to bypass it. If checks
fail, the agent has to fix the code. The hook lives in `.git/hooks/`, so
run `asimov init` or `asimov migrate` in each clone, and `asimov migrate`
after `asimov update` to refresh it.

## Development

```bash
make lint    # shellcheck on all shell scripts
make test    # bats test suite
```

Releases are automatic: when `ASIMOV_VERSION` in `bin/asimov` changes on
`main` and CI passes, CI tags `vX.Y.Z` and publishes a release with
`SHA256SUMS` and the CHANGELOG notes.

Not related to Reflection AI's Asimov or other projects with the same name.

## License

[MIT](LICENSE)

[ref]: https://github.com/mollendorff-ai/ref
[cc-perms]: https://code.claude.com/docs/en/permissions
[cc-think]: https://code.claude.com/docs/en/settings
[cc-settings]: https://code.claude.com/docs/en/settings
[cc-teams]: https://code.claude.com/docs/en/agent-teams
[gem-cli]: https://geminicli.com/docs/cli/cli-reference/
[codex-cli]: https://developers.openai.com/codex/cli/reference/

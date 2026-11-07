# Asimov

[![CI](https://github.com/mollendorff-ai/asimov/actions/workflows/ci.yml/badge.svg)](https://github.com/mollendorff-ai/asimov/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/lctavares/c99beaff02a1895916d78b8d2a8ad79d/raw/tests.json)](https://github.com/mollendorff-ai/asimov/actions/workflows/ci.yml)

**Run AI coding CLIs in full-autonomy mode, and still get good code.**

Two modes:

- `asimov` -- an interactive Claude Code, Gemini CLI or Codex CLI session
  with no approval prompts, the protocols and your roadmap loaded.
- `asimov build <specs>` -- unattended: from specs to planned, built and
  tested local git repos, with one stop for you to approve the plan.

> **Read this first.** Asimov is a personal tool. It runs AI agents with
> every approval prompt turned off, on purpose, and build mode runs them
> with nobody watching. Use it only in a sandbox (a VM, container or
> throwaway machine) where an agent with unrestricted shell access cannot
> hurt anything you care about. It is published because there is no reason
> not to, not because it is looking for users. Built with heavy AI
> assistance.

Status: personal, no stability promises. Its author uses interactive mode
in a sandbox. Build mode is new in v3.0.0: tested with mock agents and one
small real build with Claude (3 milestones, 3 runs, $0.84); Gemini and
Codex build runs are tested with mocks only.

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
- **Stop rules** -- in build mode, caps on runs, hours, spend and stalls,
  so an unattended build always ends and says why.

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

Build mode also needs `git`, plus [ref][ref] for PDF and URL specs and for
link checks, and `pandoc` for `.docx` specs. `asimov status` shows what is
installed and what is missing.

## Quick start

Interactive, in an existing project:

```bash
cd your-project
asimov init        # scaffold .asimov/, install pre-commit hook
asimov             # launch the AI with protocols + roadmap warmup
asimov migrate     # bring an older .asimov/ up to date
```

Build mode, in an empty folder:

```bash
asimov config set build.sandbox true      # once, in the sandbox
mkdir builds && cd builds
asimov build ~/specs/todo-api.md          # read, plan, stop
asimov approve --max-usd 20               # build, capped at $20
```

Anywhere:

```bash
asimov status      # tools, config, project and build in one view
asimov update      # install the latest tagged release
asimov config get  # show the config; set and unset change it
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

## Build mode

`asimov build` turns specs into finished local git repos, unattended:

```bash
asimov build spec.md https://wiki.example.com/api-spec design.pdf
# reads the specs, has the agent write a plan, then stops
asimov approve --max-usd 20   # after reviewing .asimov-build/plan.yaml
asimov resume                 # continue after any stop
asimov build --yes --max-usd 20 spec.md   # no approval stop
```

Always set `--max-usd` with Claude: a small spec cost $0.84 in testing,
but a real project can cost far more. `asimov status` in the build folder
shows the phase, the spend against the cap and the milestones released.

1. **Read specs** -- `.md` and `.txt` as they are, `.pdf` and URLs through
   [ref][ref], `.docx` through pandoc, all saved as Markdown in
   `.asimov-build/specs/`. A URL behind a login stops the build with the
   `ref login` command to run.
2. **Plan** -- one headless agent run writes `plan.yaml` (projects,
   milestones, testable acceptance criteria) and `ASSUMPTIONS.md` (every
   open decision and the choice made). Asimov checks the plan's shape.
3. **Approve** -- the build stops so you can read and edit the plan.
4. **Scaffold** -- one folder and git repo per project, with `.asimov/`,
   the pre-commit hook, the specs in `docs/specs/`, and `ref mcp`
   registered when ref is installed.
5. **Build** -- for each project in turn, the agent runs headless on the
   current milestone: tests from the acceptance criteria first, commits
   through the quality gate, and marks the milestone released when done.
   Asimov then checks README and docs links with `ref check-links` (broken
   links send it back) and moves to the next milestone from the plan.

A build never runs open-ended. It stops, says why, and `asimov resume`
continues, when any of these is hit:

- `--max-loops` agent runs for one project (default 40)
- `--max-hours` per build session (default 8)
- `--max-usd` total spend (Claude only, also passed as `--max-budget-usd`)
- `--stall` runs in a row with no new commit (default 3)
- the agent writes `BLOCKED.md` saying what it needs

Build mode needs `build.sandbox: true` in `~/.asimov/config.yaml`, set
once, on purpose. It uses lighter defaults than interactive mode (effort
`high`, no 1M thinking budget), configurable under `build:`. Projects are
built one after another, because ref's saved Chrome profile can be used by
one Chrome at a time.

With ref's saved profile, an agent browses as you, signed in. In the
sandbox, sign ref in only to the sites your specs need, never email,
banking or work accounts.

Design: [docs/design/build-mode.md](docs/design/build-mode.md).

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

Change any setting with `asimov config set <key> <value>` (keys use dots,
values are YAML, so `true`, `3` and `[--a, --b]` keep their type); add
`--project` to write `.asimov/launch.yaml` instead. `asimov config get`
prints the file or one value; `asimov config unset` removes a key.

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

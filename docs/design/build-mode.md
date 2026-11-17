# Build Mode Design

Status: implemented in v3.0.0 · 2026-11-07

## Summary

Asimov v3 adds a second mode. `asimov build <spec>...` takes one or more
specs (Markdown, text, PDF, Word or a URL), plans the work, stops once for
the owner to approve the plan, then creates the project folders and git
repos and has an AI coding CLI build everything, unattended, until every
milestone is released or a stop rule fires.

Asimov stays a conductor, not an agent. The agent is Claude Code. (This
design first allowed Gemini CLI and Codex CLI too. Since 3.4.0 build mode
runs Claude only: their build runs were never run for real, had no way to
cap spend, and could not be tested without subscriptions. They remain
available for interactive use.) Asimov adds spec ingestion, a plan approval
stop, scaffolding, a headless loop around the existing sprint protocol, and
stop rules. The pre-commit quality gate is what keeps the loop from
shipping bad code.

The two modes:

- `asimov` -- interactive session in full autonomy (today's behaviour).
- `asimov build <specs>` -- unattended, from specs to finished repos.

## Commands

```text
asimov build [options] <spec>...   ingest, plan, stop for approval
asimov approve [dir]               approve the plan and start building
asimov resume [dir]                continue after a stop or a crash
asimov build --yes <spec>...       skip the approval stop (full autonomy)
```

Options:

- `--dir <path>` -- build folder (default: current folder).
- `--ai claude` -- the agent; Claude is the only one build mode runs
  (default: `build.default_ai`, then `claude`; `launch.default_ai` is the
  interactive choice and does not apply).
- `--max-loops <n>` -- agent runs per project (default 40).
- `--max-hours <h>` -- wall-clock limit for the whole build (default 8).
- `--max-usd <amount>` -- spending cap; Claude only, passed as
  `--max-budget-usd` on each run and tracked across runs (default: none).
- `--stall <n>` -- stop a project after n runs with no new commit
  (default 3).

## Layout

```text
<build dir>/
├── .asimov-build/
│   ├── specs/            # every spec as Markdown, the source of truth
│   ├── sources.yaml      # original path or URL of each spec, Ref status
│   ├── plan.yaml         # projects, milestones, acceptance criteria
│   ├── ASSUMPTIONS.md    # what the planner guessed instead of asking
│   ├── state.yaml        # phase, current project, loop counts, spend
│   └── logs/             # one log per agent run
├── <project-a>/          # git repo with .asimov/ and the pre-commit hook
└── <project-b>/
```

`.asimov-build/` is the build's memory. `resume` reads `state.yaml` and
continues from the recorded phase, so a crash, a reboot or a stop rule never
loses work.

## Phases

```text
ingest → preflight → plan → [approval] → scaffold → execute → done
                                  │                     │
                              (stop here           stop rule fired
                              unless --yes)         → stopped
```

### 1. Ingest

Each spec becomes Markdown in `.asimov-build/specs/`:

| Input | Converter |
| ----- | --------- |
| `.md`, `.txt` | copied as is |
| `.pdf` | `ref pdf` (keeps tables and headings) |
| `.docx` | `pandoc -t gfm` |
| URL | `ref fetch`, its `content` field |

`sources.yaml` records where each spec came from and Ref's `status` for
it, so a re-run can refresh URL specs.

### 2. Preflight

Fails fast, before any agent runs, naming the fix for each problem:

- Required tools: yq (mikefarah), jq, git, the chosen AI CLI; `ref` only
  when a spec is a PDF or URL; `pandoc` only for `.docx`.
- Any URL spec whose Ref status is `login` or `paywall`: stop with
  "run `ref login <site>`, then `asimov resume`".
- Sandbox acknowledgement: `build.sandbox: true` must be set once in
  `~/.asimov/config.yaml`. Asimov cannot detect a sandbox, so it asks the
  owner to say so once, on purpose.

### 3. Plan

One headless agent run reads `.asimov-build/specs/` and writes:

- `plan.yaml`: one or more projects (name, folder, stack, description),
  each with ordered milestones; every milestone has deliverables and
  testable acceptance criteria.
- `ASSUMPTIONS.md`: every decision the specs left open, with the choice
  made. The planner never stops to ask.

One repo by default; several only when the specs describe separate
deliverables (for example an API and a client). Asimov validates
`plan.yaml` against a fixed shape with yq and fails the phase if it does
not match.

### 4. Approval

Asimov prints a short summary (projects, milestones, assumption count) and
stops. The owner reads `plan.yaml` and `ASSUMPTIONS.md`, edits them if
needed, then runs `asimov approve`. `--yes` skips this stop.

A wrong plan wastes hours; a wrong line of code is caught by the gate. This
is the one stop worth keeping.

### 5. Gate preflight and scaffold

Once the plan is approved, and before anything is built, Asimov checks that
the quality gate can run for every project's stack. The plan's stack names
the languages (Python, Rust, Node, Go, Flutter; a stack can name several),
and for each Asimov checks the tools `hooks/pre-commit` needs: for Python,
`ruff`, `pytest` and `pytest-cov` importable by `python`; for Rust, `cargo`,
rustfmt, clippy and `cargo-llvm-cov`; for Go, `gofumpt`, `golangci-lint` and
`go-test-coverage`; for Flutter, `flutter` and `lcov`; for Node, `npm`. A
missing tool stops the build with its install command, and `asimov resume`
continues. Every commit goes through the gate, so without this the first
paid run would end at its first commit.

For each project, in plan order: create the folder, `git init`,
`asimov init`, write `project.yaml` and `roadmap.yaml` from the plan (first
milestone as `current` with status `autonomous`, the rest as `backlog`),
copy the relevant specs into the project's `docs/specs/`, and register
`ref mcp` in the agent's MCP config (Claude: `.mcp.json`), rooted to the
project folder.

### 6. Execute

Projects are built one after another (see Ref constraint). For each
project, a loop:

1. Run the agent headless in the project folder with the protocols and
   this prompt: work on the current milestone in `.asimov/roadmap.yaml`;
   write tests from the acceptance criteria first; commit through the
   pre-commit gate; when every deliverable is done, follow the sprint
   protocol's completion steps.
2. After the run, read the roadmap. If the milestone is `released`, promote
   the next backlog item to `current` (status `autonomous`). If none is
   left, the project is done.
3. Check stop rules (below). Record the run in `state.yaml` and `logs/`.

Headless command: `claude -p <prompt>` plus launch args,
`--append-system-prompt`, `--output-format json` (the run's cost is read
from it) and `--max-budget-usd` when a cap is set. The planning run uses
the same flags, so its cost counts toward `--max-usd` too.

### 7. Release checks

Before accepting a milestone as released:

1. **Quality gate on HEAD (always).** The agent runs with no approval
   prompts, so it can commit with `git commit --no-verify` or weaken the
   project's `.git/hooks/pre-commit`. Asimov runs its own shipped hook, not
   the project's, against a temporary index read from HEAD
   (`GIT_INDEX_FILE=<tmp> git read-tree HEAD`). The hook copies the index
   to a temporary folder and checks it there, so this checks exactly what
   was committed: an uncommitted fix does not count, uncommitted junk does
   not block. Output goes to `logs/gate-<project>.log`. A failure sends the
   milestone back: the roadmap is rewritten from the plan (status
   `autonomous`, which also undoes an agent that moved the milestone
   itself), and the next run's prompt carries the end of the gate output.
   A missing shipped hook stops the build rather than skipping the check.
2. **Links (when `ref` is installed).** `ref check-links` on the project's
   README and `docs/`. Dead links send the milestone back the same way,
   with the report.

The gate runs only when a run claims a release, not after every run.

## Stop rules

A build never runs open-ended. It stops, records why in `state.yaml`, and
prints the reason when any of these fires:

- Loop cap: `--max-loops` runs for one project.
- Time cap: `--max-hours` since the build started (default 8).
- Spend cap: `--max-usd` reached (Claude).
- Stall: `--stall` runs in a row with no new commit in the project.
- Gate failures: `--stall` releases in a row whose committed code fails the
  quality gate (the counter resets when the gate passes).
- The agent writes `BLOCKED.md` in the project (the loop prompt tells it to
  do so when it cannot continue, with the reason).

`asimov resume` continues after the owner fixes the cause; caps can be
raised with the same options.

## Model and cost defaults

Interactive mode keeps its maximum settings. Build mode runs many turns, so
it gets its own defaults in `~/.asimov/config.yaml`:

```yaml
build:
  default_ai: claude
  sandbox: false          # set to true once, on purpose
  claude:
    model: opus
    env:
      CLAUDE_CODE_EFFORT_LEVEL: "high"
```

Interactive mode runs at effort `max`; build mode runs at `high`. The owner
can change it under `build.claude.env`.

## Ref integration

Ref is optional and used in three places:

1. Ingest: `ref fetch` for URL specs, `ref pdf` for PDF specs; `login` or
   `paywall` status stops the build in preflight.
2. During the build: `ref mcp` registered per project, rooted to the
   project folder, so the agent reads docs and API references through Ref.
3. Release check: `ref check-links` on README and docs.

Constraint: Ref's saved Chrome profile can be used by one Chrome at a
time. Asimov builds projects one after another, never in parallel, so only
one agent uses Ref at a time.

Risk: with the saved profile, an agent using Ref browses as the owner,
signed in, with no approval prompts. In the sandbox, use a Ref profile that
is signed in only to the sites a build needs, never email, banking or work
accounts. The README states this next to the sandbox warning.

## Testing

Same approach as `test/launch.bats`: mock AI CLIs, `ref` and `pandoc` that
record arguments and write scripted outputs.

- Ingest: each input type lands as Markdown; `login` status stops preflight.
- Plan: a malformed `plan.yaml` fails the phase; approval stop happens by
  default and is skipped with `--yes`.
- Scaffold: folders, git repos, `.asimov/`, roadmaps and MCP config match
  the plan.
- Execute: milestone promotion; each stop rule fires and is recorded;
  `resume` continues from every phase.
- Shellcheck on all scripts; no network in tests.

## Out of scope for v3.0.0

- Building projects in parallel.
- Deploying anything (servers, app stores, package registries).
- Pushing to GitHub or opening pull requests; repos stay local.
- A web or graphical interface.

## Decisions made during implementation

- Headless command: `claude -p`. (3.0 to 3.3 also had `gemini -p` and
  `codex exec --skip-git-repo-check`; removed in 3.4.0, see the Summary.)
- Build mode stays in `bin/asimov`, so install and update keep shipping one
  script. Splitting it into modules was considered and dropped.
- The next milestone always comes from `plan.yaml`, not from the agent's
  edits to the roadmap; an agent that moves the milestone itself is
  treated as having released it.
- The time cap counts per build session, so `resume` gets a fresh window.
- `resume` after a stop resets the stall and gate-failure counters; loop
  counts and spend carry over.
- Repos get a local commit identity (`Asimov Build`) when git has none.
- The plan run gets no protocols; its prompt carries the full instructions.
- The scaffold makes no commit; the agent's first commit goes through the
  pre-commit gate like every other.

## Delivery

- v3.0.0-alpha.1: ingest, preflight, plan, approval, scaffold.
- v3.0.0: execute loop, stop rules, resume, release check, README.

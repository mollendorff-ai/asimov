# Changelog

## 3.5.1

- `asimov migrate` says only what it changed. In a git repo it used to
  print "Updated pre-commit hook" and "Migration complete" on every run,
  even when the hook was already current; it now copies the hook, and says
  so, only when it is missing or differs from the shipped one, and
  otherwise reports "Already up to date." (The tests never ran migrate in
  a git repo, which is why this was missed.)
- `asimov migrate` no longer calls a protocol file "edited" when it holds
  the same JSON as the shipped one and differs only in whitespace, such as
  a missing final newline. It leaves that file alone and says nothing.
  A file whose content differs is still kept and flagged, with the
  differences shown.

## 3.5.0

- `asimov migrate` no longer deletes the files and folders that asimov 1.x
  left in `.asimov/` (`warmup.json`, `asimov.json`, `green.json`,
  `migrations.json`, `roles/`, `templates/`, `hooks/`, `protocols/`). They
  now show up under "Unexpected files" for you to remove by hand, like any
  other stray file. Run the 3.4.0 or earlier migrate once on any project
  that still has them if you want them removed automatically.
- New global configs no longer set `MAX_THINKING_TOKENS`. Current Claude
  Code models (Opus 4.7 and later, Sonnet 5 and later) always use adaptive
  reasoning, where the effort level sets the depth and a fixed thinking
  budget does nothing. The defaults that remain are the ones that act:
  `CLAUDE_CODE_EFFORT_LEVEL: max`, which Claude Code still accepts, and
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: 1`, which is still experimental
  and works in interactive sessions only (build mode runs headless). An
  existing `~/.asimov/config.yaml` is left alone; delete the
  `MAX_THINKING_TOKENS` line if you want it gone.
- The README says agent teams are experimental, interactive-only and use
  many more tokens, and links the effort levels to the model configuration
  page.

## 3.4.0

- Build mode re-runs the quality gate itself before a milestone counts as
  released. The agent runs with no approval prompts, so it can commit with
  `git commit --no-verify` or weaken the project's own hook; until now it
  was only told not to. Asimov runs its shipped pre-commit hook (not the
  project's copy) on the committed code, using a temporary index read from
  HEAD, so an uncommitted fix does not count and uncommitted files do not
  block. A failure sends the milestone back with the end of the gate output
  in the next run's prompt, and the full output in
  `.asimov-build/logs/gate-<project>.log`. `--stall` failures in a row stop
  the build with their own reason; `asimov resume` resets the count. A
  broken-links report now also restores the roadmap from the plan, so an
  agent that moved the milestone itself no longer skips it.
- Build mode checks the quality gate's tools before the first paid run:
  `ruff`, `pytest` and `pytest-cov` for Python, `cargo`, `rustfmt`, clippy
  and `cargo-llvm-cov` for Rust, the Go and Flutter tools, and `npm` for
  Node, for every language a project's stack names. A missing tool stops the
  build with its install command, and `asimov resume` continues. The first
  real build lost a paid run to a missing `pytest-cov`.
- Build mode runs Claude only. Gemini CLI and Codex CLI are removed from it:
  they were never run for real, have no spend cap, and there are no
  subscriptions to test them with. `--ai gemini`, `--ai codex` and a
  `build.default_ai` naming them are refused with the reason, `asimov
  resume` refuses a build that used them and changes nothing, and
  `launch.default_ai` no longer picks the build agent. Interactive launch
  still supports all three.
- The README and SECURITY.md say that `SHA256SUMS` only catches corruption,
  not tampering, and that releases are not signed.

## 3.3.0

- `asimov migrate` brings protocol files up to date. A project copy that is
  an older version asimov shipped is replaced; one you edited is kept, with
  its differences from the shipped file shown so you can merge by hand.
  Before, migrate only copied a protocol when it was missing, so a project
  kept its old rule text after `asimov update`. Run `asimov migrate` in
  each project after updating.
- `.asimov/project.yaml` records a `format` version, written by `init` and
  set or raised by `migrate`. `migrate` refuses a project whose format is
  newer than the installed asimov understands, and changes nothing;
  `asimov status` flags a missing, old or newer format.
- The current sprint is part of the agent's prompt, and asimov prints a
  one-line sprint summary at launch. Claude no longer gets a separate
  warmup turn followed by `--continue`: that turn cost a model call at
  maximum effort on every launch, and a failure in it stopped the launch
  before a session started. Gemini and Codex get the sprint in their first
  message, as they got the protocols.

## 3.2.0

- Quality gate: the pre-commit hook checks the staged snapshot (what the
  commit will contain), not the working tree. It copies the index to a
  temporary folder and runs every check there, honouring `GIT_INDEX_FILE`
  for partial commits. A commit can no longer pass on files that are not
  staged, and the work tree is never touched. Installed dependency folders
  are linked in; Rust builds reuse `target/`. A check that needs a
  git-ignored file must have it staged. Projects get the new hook with
  `asimov migrate`.

## 3.2.1

- Build mode scaffold: the project type in `.asimov/project.yaml` comes
  from the plan's stack (rust, python, node, go or flutter, first match,
  any case) instead of always being `generic`, and the scaffold log no
  longer ends with the interactive-mode "run asimov to start" advice.
  `asimov init` by hand is unchanged.

## 3.1.1

- Build mode: the planning run counts toward `--max-usd`. It gets the
  remaining budget as `--max-budget-usd`, its cost is added to the spend,
  and `asimov resume` refuses to plan again once the budget is spent.
- Build mode: the Python quality gate runs `python -m pytest` through the
  interpreter it checked for pytest-cov, so a stray `pytest` on PATH can no
  longer block every commit.

## 3.1.0

- `asimov status`: one view of tools (yq flavour, jq, AI CLIs, ref,
  pandoc), config (default AI, `build.sandbox`), the project (protocols,
  description, roadmap, pre-commit hook up to date, `BLOCKED.md`) and a
  build in the folder (phase, stop reason, spend against the cap, released
  milestones per project); lists issues with their fix
- `asimov config get|set|unset|path [--project]`: read and change
  `~/.asimov/config.yaml` or `.asimov/launch.yaml` with dotted keys; values
  are YAML, so booleans, numbers and lists keep their type
- Tests: 161 (17 new)

## 3.0.0

- Build mode is complete: after scaffolding, each project is built
  unattended, milestone by milestone, one project after another
- Execute loop: the agent runs headless with the protocols and a loop
  prompt (tests from acceptance criteria first, commit through the gate,
  mark released, write `BLOCKED.md` when stuck); Asimov promotes the next
  milestone from `plan.yaml`
- Stop rules: `--max-loops`, `--max-hours`, `--max-usd` (Claude, tracked
  from each run's cost and passed as `--max-budget-usd`), `--stall`, and
  `BLOCKED.md`; caps work on `build`, `approve` and `resume`
- Release check: `ref check-links` on README and docs; broken links send
  the milestone back with the report
- `asimov resume` continues from any stop and can raise caps
- Repos get a local commit identity when git has none
- Tests: 144 (16 new for the execute loop and every stop rule)

## 3.0.0-alpha.1

- New `asimov build <spec>...`: reads `.md`, `.txt`, `.pdf` (ref),
  `.docx` (pandoc) and URL (ref) specs into `.asimov-build/specs/`; stops
  before planning when a URL spec is behind a login or paywall
- Planning: one headless agent run writes `plan.yaml` and
  `ASSUMPTIONS.md`; Asimov validates the plan's shape (names, milestones,
  deliverables, acceptance criteria)
- Approval stop by default; `asimov approve` continues, `--yes` skips it
- Scaffold: one folder and git repo per project with `.asimov/`, the
  pre-commit hook, roadmap from the plan (first milestone `autonomous`),
  specs in `docs/specs/`, `ref mcp` registered for Claude and Gemini
- `asimov resume` continues from the recorded phase and re-reads specs
  that were behind a login
- Build mode requires `build.sandbox: true` and uses lighter defaults
  (effort `high`, no 1M thinking budget)
- Tests: 128 (25 new for build mode, with mock AI CLIs, ref and pandoc)

## 2.12.0

- README reframed: personal tool for sandboxed full-autonomy use, with a
  plain warning, status line, AI-assistance note and per-AI table
- Gemini CLI and Codex CLI now get the protocols and roadmap warmup as the
  first message (`--prompt-interactive` for Gemini, initial prompt for
  Codex); previously only Claude got them
- Gemini default flag `--yolo` (deprecated) replaced by
  `--approval-mode=yolo`
- `check_deps` detects the Python `yq` that `apt install yq` provides and
  stops with instructions for mikefarah/yq instead of failing mid-launch
- `migrate_global_config` writes only when a key is missing, so launching
  no longer rewrites `~/.asimov/config.yaml` (or strips its comments)
- `asimov migrate` no longer deletes `CLAUDE.md`, `GEMINI.md` or
  `CODEX.md`; it keeps them and prints a note
- `asimov update` and `install.sh` install the latest tagged release and
  verify every file against the release's `SHA256SUMS`; nothing is changed
  if a check fails
- CI `release` job tags and publishes a release when `ASIMOV_VERSION`
  changes on main; `install.sh` is now shellchecked
- `freshness.json`: prefer `ref fetch` when `ref` is installed, instead of
  forbidding the built-in web tools outright
- Pre-commit hook: Python lint uses the project's ruff config when present
  (`ruff.toml`, `.ruff.toml`, or `[tool.ruff]` in pyproject.toml) and falls
  back to `--select ALL`; header no longer claims an organizational mandate
- Protocol file list defined once (`ASIMOV_PROTOCOLS`)
- Tests: 103 (new launch tests for all three AIs, yq flavour, ruff config,
  checksum-verified update; tool-missing tests no longer depend on the host
  PATH)

## 2.11.0

- Add `asimov update`: fetch latest release from GitHub, replace binary
  and protocols in-place; skips if already up-to-date
- Update README with `asimov update` command
- 10 new bats tests for update command (95 total)

## 2.10.0

- Add `install.sh`: curl one-liner installs asimov from
  GitHub without cloning (bin, protocols, pre-commit hook)
- Update README with curl install method

## 2.9.0

- Roadmap format: single `current` milestone, add `previous`
  and `backlog` fields (aligned with old Rust schema)
- Sprint protocol: full lifecycle — on completion, update
  roadmap, append to CHANGELOG.md, discuss next from backlog
- Init template generates new roadmap format with `backlog: []`

## 2.8.0

- Add `CLAUDE_CODE_EFFORT_LEVEL: max` and
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: 1` to default
  global config (new installs get both automatically)
- Auto-migrate existing `~/.asimov/config.yaml`: inject
  missing env vars without overwriting user customizations
- Add "Why these defaults" section to README explaining
  all launch settings for Claude Code, Gemini CLI, Codex CLI
- 7 new bats tests for global config migration (85 total)

## 2.7.0

- Reframe README: lead with the problem (AI sessions
  start cold), position as developer tooling for
  AI-assisted workflows
- Add CONTRIBUTING.md (dev setup, project structure,
  PR guidelines, how to add protocols and languages)
- Add GitHub issue templates (bug report, feature request)

## 2.6.0

- Add GitHub Actions CI: shellcheck lint + bats tests
  on push and PR
- Add `make lint` target (shellcheck on all shell scripts)
- Fix shellcheck SC2163 warning in env var export

## 2.5.0

- Add test suite with bats-core (77 tests)
  - Config helpers: cfg_get, cfg_list, cfg_env
  - Init command: scaffolding, type detection, hook install
  - Migrate command: cruft removal, project.yaml enrichment, orphan detection
  - System prompt builder: JSON output, protocol injection
  - AI detection: is_inside_session, detect_ai, ensure_global_config
  - Pre-commit hook: language detection, failure modes, structure
- Update Makefile: `make test` runs bats test suite

## 2.4.0

- Enrich `project.yaml` with `description`, `stack`,
  `conventions` fields (gives LLM context about the
  project without expensive codebase exploration)
- `build_system_prompt` injects new fields into AI context
- `init` generates project.yaml with TODO placeholders
- `migrate` adds missing fields to existing project.yaml
  (surgical: preserves existing values, removes legacy keys)
- `launch` warns if description is empty or still TODO

## 2.3.0

- Bring back `coding-standards.json` as fourth core
  protocol (was dropped in 2.1.0 as hook-only concern;
  restored because code quality principles steer AI
  behavior beyond what pre-commit hooks enforce)
- `init` installs all 4 protocols
- `migrate` adds `coding-standards.json` if missing
  (no longer treated as cruft)
- System prompt includes coding-standards rule
- Self-contained `rule` field replaces old
  "see project.yaml" indirection

## 2.2.0

- Replace awk YAML/JSON parsing with `yq` and `jq`
- Build compact JSON system prompt via `jq`
- Add `asimov migrate` for existing projects
  (removes old cruft, slims project.yaml,
  flags orphan files)
- Dependency check with install instructions
- Fix `cfg_get` returning non-zero on empty values

## 2.1.0

- Inject protocols via `--append-system-prompt`
  (never compacted, always active)
- Warmup via `-p` forces roadmap reading,
  then `--continue` for interactive session
- Drop `coding-standards.json`
  (pre-commit hook is the quality enforcer)
- Drop bootstrap files
  (CLAUDE.md, gemini.md, codex.md)
- Strip quality/files sections from project.yaml
- Warn when `asimov init` runs outside a git repo
- Clean repo: fresh history, no Rust baggage

## 2.0.0

- Replace 16K-line Rust binary with ~335-line shell
- Keep 4 behavioral protocols as plain JSON
- Keep pre-commit hook (format + lint + 100% coverage)
- Per-vendor bootstrap files (CLAUDE.md, gemini.md,
  codex.md)
- YAML config: global + per-project overrides
- MIT license (was ELv2)

## Pre-2.0

The earlier Rust CLI is kept privately and archived; it is not
maintained or published here.

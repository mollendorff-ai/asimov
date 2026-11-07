# Changelog

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

Rust CLI archived at `mollendorff-ai/asimov-rust`.
Tagged `v14.1.0-rust-final`.

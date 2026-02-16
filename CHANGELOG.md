# Changelog

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

# Changelog

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

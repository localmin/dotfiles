# Vendored external skills

A mechanism for fetching and using agent skills from external repositories at a
**pinned commit**. It pulls in skills that mizchi distributes via APM, adapting
them to this dotfiles' existing model (`coding-agents/skills/<name>/` →
`install.sh` symlinks them to the Claude / Antigravity / Codex CLIs).

## Policy

- **Mechanism is tracked** (this directory: `manifest.tsv` / `fetch.sh` / `README.md`).
- **Payload is untracked** (expanded into `coding-agents/skills/<name>/`, excluded by `coding-agents/skills/.gitignore`).
  We do not vendor other repos' code into our own repo; we fetch from upstream each
  time, and the pin guarantees reproducibility.
- Provenance is stated in three layers: `manifest.tsv` (single source of the pin),
  each skill's `.upstream`, and the table in this README.

## Usage

```bash
coding-agents/vendor/fetch.sh              # (re)fetch all skills at their pinned commits
coding-agents/vendor/fetch.sh --if-missing # fetch only what is missing (called by install.sh during bootstrap)
coding-agents/install.sh                   # after fetching, symlink to the 3 CLIs
```

On a fresh machine `coding-agents/install.sh` calls `fetch.sh --if-missing` first, so
`clone` → `install.sh` is enough to also bring in the vendored skills.

## Updating (tracking upstream)

The pin does not follow upstream automatically (so versions do not drift between
machines). To move to the latest:

1. Update `PIN=` in `manifest.tsv` to the new commit / tag
2. Run `coding-agents/vendor/fetch.sh`
3. Review the diff and commit

## Vendored skills

Pinned per block in `manifest.tsv`. Upstream sources:

- [mizchi/skills](https://github.com/mizchi/skills) — license: MIT (repo default)
- [ast-grep/agent-skill](https://github.com/ast-grep/agent-skill) — no upstream license (payload is gitignored, not redistributed)
- [obra/superpowers](https://github.com/obra/superpowers) — license: MIT
- [ogulcancelik/herdr](https://github.com/ogulcancelik/herdr) — AGPL-3.0-or-later (dual-licensed AGPL/commercial; payload is gitignored, not redistributed)
- [inkdropapp/skills](https://github.com/inkdropapp/skills) — no upstream license (its README says so; payload is gitignored, not redistributed)

| local name | source | upstream path | purpose |
|---|---|---|---|
| retrospective-codify | mizchi/skills | meta/retrospective-codify | codify learnings into ast-grep rules / CLAUDE.md / skills |
| ast-grep-practice | mizchi/skills | tooling/ast-grep-practice | how-to for running ast-grep as a project lint |
| optimizing-descriptions | mizchi/skills | meta/optimizing-descriptions | audit and rewrite SKILL.md descriptions |
| empirical-prompt-tuning | mizchi/skills | meta/empirical-prompt-tuning | empirical instruction tuning via a subagent executor |
| waxa-eval | mizchi/skills | meta/waxa-eval | operating manual for the `waxa` CLI (skill eval) |
| ast-grep | ast-grep/agent-skill | ast-grep/skills/ast-grep | authoritative ast-grep rule-writing reference (rule_reference.md) for structural code search |
| test-driven-development | obra/superpowers | skills/test-driven-development | TDD loop discipline: verified-RED before GREEN, no implementation-conforming tests (gate: vendor/evals/test-driven-development/) |
| herdr | ogulcancelik/herdr | SKILL.md | drive the herdr terminal multiplexer from inside it (only active when HERDR_ENV=1) |
| note-taking | inkdropapp/skills | skills/note-taking | Inkdrop markdown dialect: code-fence attributes, mermaid, KaTeX, `inkdrop://note/<id>` links (gate: vendor/evals/note-taking/) |

### Runtime dependencies (note)

`waxa-eval` invokes the `waxa` CLI at runtime (`npx @mizchi/waxa`,
requires an authenticated `claude` CLI). The SKILL.md files are documentation and
read fine from vendoring alone, but actually running an eval needs the CLI via npx.

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

Source: <https://github.com/mizchi/skills> (`PIN` is in `manifest.tsv` / license: MIT, repo default)

| local name | upstream path | purpose |
|---|---|---|
| retrospective-codify | meta/retrospective-codify | codify learnings into ast-grep rules / CLAUDE.md / skills |
| ast-grep-practice | tooling/ast-grep-practice | how-to for running ast-grep as a project lint |
| optimizing-descriptions | meta/optimizing-descriptions | audit and rewrite SKILL.md descriptions |
| skill-selector | meta/skill-selector | pick skills to adopt from a curated catalog |
| skill-finder | meta/skill-finder | cross-source skill discovery + waxa eval gate |
| empirical-prompt-tuning | meta/empirical-prompt-tuning | empirical instruction tuning via a subagent executor |
| waxa-eval | meta/waxa-eval | operating manual for the `waxa` CLI (skill eval) |

### Runtime dependencies (note)

`waxa-eval` / `skill-finder` invoke the `waxa` CLI at runtime (`npx @mizchi/waxa`,
requires an authenticated `claude` CLI). The SKILL.md files are documentation and
read fine from vendoring alone, but actually running an eval needs the CLI via npx.

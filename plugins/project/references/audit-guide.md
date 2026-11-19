# Audit guide (for /project:update)

Compare an existing project against `plan-checklist.md` and classify every area as **present**, **partial**, **missing**,
**not applicable** or **excluded on purpose**. Read-only: detect, never change. Cite the evidence (file path or command
output) for every verdict. Don't judge quality beyond "does it work and match the project's own stack".

## Detect first

- Stack: manifests (`package.json`, `composer.json`, `go.mod`, `pyproject.toml`, `Cargo.toml`, `Gemfile`, ...), lockfiles,
  runtime pin files (`.nvmrc`, `.tool-versions`, `.python-version`), framework configs, top-level directory layout.
- Project type (web app, API, CLI, library, ...). It decides which areas apply.
- Prior wizard artefacts: `PROJECT_PLAN.md` (read its decision log, "Not included" and "Deviations": those are decisions
  already made), `.project-setup/decisions.md`, `CLAUDE.md`, `README.md`, `docs/adr/`.
- Git: `git remote -v`, default branch, forge (github | gitlab | other), `gh auth status` / `glab auth status`.

## Signals per area

| Area | Present when |
|---|---|
| Foundation | `.gitignore`, `.gitattributes`, `.editorconfig`, licence, runtime pin file, lockfile committed, task runner (Makefile/justfile/package scripts) |
| Formatting & linting | formatter and linter configs (`.prettierrc`, `eslint.config.*`, `ruff`/`pyproject` sections, `.golangci.yml`, `pint.json`, `rustfmt.toml`, ...) |
| Static analysis / types | `tsconfig.json` strict, `mypy`/`pyright`, `phpstan.neon`, `go vet`/staticcheck config, clippy settings |
| Tests | test dir, runner config, at least one test, coverage config/threshold |
| Git hooks & commits | `.husky/`, `lefthook.yml`, `.pre-commit-config.yaml`, `commitlint` config, `core.hooksPath` |
| Security | dependency audit step, secret scanning (gitleaks), SAST/CodeQL, `SECURITY.md` |
| App skeleton | config loading + `.env.example`, logging, error handling, health endpoint |
| Data & services | migration tool + migrations, seed, compose services for cache/queue/search/storage/mail |
| Containers | `Dockerfile` (multi-stage, non-root, healthcheck), `.dockerignore`, `compose.y*ml`, `.devcontainer/` |
| CI | `.github/workflows/`, `.gitlab-ci.yml`: lint, types, tests, build, security, caching, `permissions:` |
| CD & releases | deploy workflow/config, release automation, changelog tooling |
| Dependency updates | `renovate.json`, `.github/dependabot.yml` |
| Observability | error tracking SDK, structured logging, metrics/tracing config |
| IaC | `terraform/`, `pulumi`, `cdk`, `helm/`, `k8s/` |
| Docs & community | README (quick start, commands), CONTRIBUTING, PR/issue templates, CODEOWNERS, ADRs |
| Claude | `CLAUDE.md` (commands, architecture, conventions), `.claude/settings.json` (allow/deny), rules, `.mcp.json`, `.claude/harness.md` |

## Output: the audit report

A table `Area | Status | Evidence | Note`, then three lists: **Missing**, **Partial** (what exactly is lacking),
**Looks off** (stale versions, CI commands that differ from local ones, contradictions between README and reality).
Keep it scannable; no prose per row.

## Turning gaps into interview topics

Ask only about gaps, and make existing tools the baseline: a missing linter in a TypeScript repo that already uses Prettier gets
"ESLint or Biome? (Biome overlaps with the Prettier you already have)", never a blank-slate stack question. Recommended
options must fit what is there; don't propose replacing working tools unless the user asks. Areas that are present are
recorded as `Detected` and are not re-asked.

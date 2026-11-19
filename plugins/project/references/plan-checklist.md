# Plan completeness checklist (self-audit)

Run before finishing. Each item is **covered**, **explicitly excluded with a reason** (in "Not included"), or **not applicable**.
"Forgotten" is the only wrong state.

## Plan quality
- [ ] Every row in decisions.md appears in the decision log and is implemented in a phase
- [ ] Zero "TBD", "as discussed", "see above conversation", or unresolved choices
- [ ] Versions and scaffold commands verified on the web (date recorded) or marked "verify at build time"
- [ ] Every phase has acceptance checks with expected results; final verification section exists
- [ ] Manual steps separated, ordered, and specific; the plan never asks the executor to enter secrets
- [ ] Skeleton only: one proof-of-life slice, no features; ideas moved to "Later"
- [ ] A cold reader can start Phase 1 with only this file

## Project foundation
- [ ] Name, licence, `.gitignore`, `.gitattributes`, `.editorconfig`, runtime version pin file, initial commit/branch strategy
- [ ] Package manager pinned, lockfile committed, scripts/task runner with `setup dev test lint fmt build ci`
- [ ] Directory structure, module boundaries and how they're enforced; naming conventions

## Code quality
- [ ] Formatter + linter + type checker/static analysis at chosen strictness; configs printed
- [ ] Test runner, test layout, one passing test per layer chosen, coverage tool and threshold (or "none" with a reason)
- [ ] Git hooks and commit convention; hooks installable by one command
- [ ] Security: dependency audit, secret scanning, SAST, container scan (as chosen); `SECURITY.md` if public

## Application skeleton
- [ ] Config loading and validation, `.env.example`, no secrets in git, per-environment config
- [ ] Error handling, logging (structured), health endpoint/readiness where applicable
- [ ] Database: connection, migration tool, first migration, seed, local reset command, test DB strategy
- [ ] Other services chosen (cache, queue, search, storage, mail, auth, payments, realtime): wired with local dev equivalents
- [ ] API: style, validation, error format, docs generation (OpenAPI), versioning approach
- [ ] Frontend: build tooling, routing, styling, state/data fetching, a11y/i18n baseline (as chosen)

## Delivery
- [ ] Dockerfile (multi-stage, non-root, healthcheck), `.dockerignore`, compose with all backing services, or "no Docker" reason
- [ ] CI: lint, types, tests with services, build, security, caching, concurrency, least-privilege permissions; same commands as local
- [ ] CD/hosting and environments (or "deferred" with reason); release/versioning/changelog automation as chosen
- [ ] Dependency update bot configured
- [ ] Observability: error tracking, logs, metrics/tracing as chosen
- [ ] IaC as chosen; secrets management approach documented

## Collaboration & docs
- [ ] README (what, why, quick start in ≤5 commands, commands table, architecture link), CONTRIBUTING, PR/issue templates, CODEOWNERS
- [ ] ADRs for the major decisions made in this setup
- [ ] Forge settings listed as manual steps (branch protection, required checks, secrets, environments)

## Claude
- [ ] `CLAUDE.md`: commands, architecture, conventions, gotchas; kept short, references docs rather than duplicating
- [ ] `.claude/settings.json` with safe allow-list and destructive-command denies; rules/MCP/hooks as chosen
- [ ] Harness (if chosen): manual `/plugin marketplace add chriha/claude-plugins` + `/plugin install harness@chriha`;
      `/harness:init` run after the skeleton exists; stack pack (laravel | go | none → commands filled in `.claude/harness.md`);
      tracker/forge/labels; note that harness guards refuse lockfile edits by harness agents, so dependencies are installed before handing over

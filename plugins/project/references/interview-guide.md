# Interview guide

Topics per round. **Ask only what applies and what the idea hasn't already answered.** For each topic: if the user is unsure,
recommend per `recommendations.md`. "Applies to" says which project types need it.

## Round 1: Foundations (all types)

| Topic | Ask / decide |
|---|---|
| Goal & success | What does v1 need to prove? Who uses it? (already from discovery) |
| Team | Solo or team? Skills they already have (languages, frameworks)? Who maintains it in a year? |
| Scale & performance | Expected users / requests / data volume now and in 12 months; latency or throughput targets; offline needs |
| Timeline & budget | Prototype vs. production-grade; hosting budget; willingness to pay for managed services |
| Data sensitivity & compliance | Personal data (GDPR), payments (PCI), health (HIPAA), auth-critical? Drives hosting region, logging, encryption |
| Repo layout | Single package, or monorepo (apps + shared packages)? Monorepo tool if JS/TS (pnpm workspaces, Turborepo, Nx); polyglot (Bazel/just) |
| Naming | Project name, org/namespace, package/module name, licence holder |
| Platforms | Which OS / browsers / devices / min runtime versions must be supported? |
| Open source? | Public or private; drives licence, community files, CI secrets handling |

## Round 2: Stack (by type)

| Topic | Applies to | Ask / decide |
|---|---|---|
| Language | all | Pick by fit (see recommendations). Typed languages preferred for long-lived code. Strictness level (TS `strict`, mypy/pyright strict) |
| Runtime & versions | all | Version policy (current LTS), version pinning file (`.tool-versions`/`mise.toml`/`.nvmrc`/`go.mod`) |
| Framework | web, API, mobile, desktop | Full-stack vs. separate frontend/backend; rendering model (SSR/SSG/SPA) |
| Frontend | web, desktop | UI library, styling (Tailwind/CSS modules), component library/design system, state and data fetching, forms, routing |
| API style | API, web | REST (+ OpenAPI), GraphQL, tRPC, gRPC; versioning; validation library; API docs |
| Architecture | web, API, backend | Modular monolith (default), layered/hexagonal, microservices (only with a real reason), serverless, event-driven. Folder structure, module boundaries, how boundaries are enforced (lint rules, arch tests) |
| Package manager | all | One, pinned, lockfile committed |
| Mobile | mobile | Native vs. cross-platform (Flutter, React Native/Expo, Kotlin/Swift); OTA updates; store accounts |
| CLI/library specifics | CLI, library | Arg parsing lib, distribution (npm, PyPI, crates.io, Homebrew, binaries), semver and release tooling, public API surface and docs, supported runtime matrix |
| Data/ML | data | Orchestrator, notebooks vs. scripts, experiment tracking, data versioning, environments (uv/conda) |

## Round 3: Data & services

| Topic | Ask / decide |
|---|---|
| Primary database | Relational default (PostgreSQL). Alternatives only for a stated reason (document, graph, time series, embedded/SQLite). Managed vs. self-hosted |
| ORM / query layer | ORM vs. query builder vs. raw SQL + codegen; migration tool; seeding; local data reset |
| Cache | Needed at all? Redis/Valkey, in-memory. Skip until a measured need unless the idea implies it |
| Background jobs / queues | Email, webhooks, imports → job queue (framework-native, BullMQ, Celery, Sidekiq, River, Oban). Scheduler/cron |
| Search | DB full-text first; Meilisearch/Typesense/OpenSearch only if search is core |
| File/object storage | S3-compatible, local volume in dev, CDN, upload limits, virus scanning |
| Email / notifications | Transactional provider (Postmark, Resend, SES), local mail catcher in dev (Mailpit), templates, push/SMS |
| Auth | Own (sessions/JWT/passkeys) vs. provider (Clerk, Auth0, Supabase Auth, Keycloak, framework built-in). Social login, MFA, roles/permissions model, multi-tenancy |
| Payments | Stripe/Paddle/LemonSqueezy; webhooks; tax handling |
| Realtime | WebSockets/SSE/long-poll/pub-sub |
| AI/LLM features | Provider, SDK, prompt/eval storage, vector DB (pgvector first), cost limits, key handling |
| Third-party APIs | List them; sandbox keys; wrapper/adapter boundary; rate limits |
| Analytics / feature flags | Product analytics, flags (env-based first) |
| Backups / data lifecycle | Backup policy, retention, migration strategy, GDPR deletion/export |

## Round 4: Quality

| Topic | Ask / decide |
|---|---|
| Test strategy | Unit, integration (real DB via containers/testcontainers), e2e (Playwright/Cypress), contract tests for APIs, snapshot tests (sparingly). Test runner, coverage tool and **threshold** (suggest realistic: 70-80% lines, enforced in CI, or none for a prototype) |
| Test data | Factories/fixtures, seeded DB, time and randomness control |
| Static analysis | Type checker (strict), linter, complexity limits, dead-code detection, architecture rules, dependency-cycle check. Level/strictness and baseline strategy for existing code |
| Formatting | One formatter, format-on-save config, CI check. `.editorconfig` always |
| Git hooks | pre-commit (format + lint on staged), commit-msg (conventional commits), pre-push (tests). Tool: lefthook / husky / pre-commit / native `core.hooksPath` |
| Commit & release convention | Conventional Commits + automated changelog/versioning (release-please, semantic-release, changesets, goreleaser), or manual |
| Security scanning | Dependency audit, secret scanning (gitleaks), SAST (CodeQL/semgrep), container scan (Trivy), licence check |
| Performance | Benchmarks, load-test scaffold (k6), bundle-size budget, Lighthouse CI |
| Accessibility / i18n | a11y linting and axe tests for UIs; i18n library and locale files from day one if multilingual |

## Round 5: Delivery

| Topic | Ask / decide |
|---|---|
| Containers | Dockerfile (multi-stage, non-root, pinned base, `.dockerignore`) and `docker-compose` for app + backing services with healthchecks; dev hot-reload. Or devcontainer. Or none (say why) |
| Dev environment | One-command bootstrap (`make setup` / `just setup`), tool-version manager, `.env.example`, seed data, README quick start |
| Task runner | Makefile / justfile / package scripts / Taskfile as the single entry point (`setup, dev, test, lint, fmt, build, ci`) |
| CI | Provider (GitHub Actions, GitLab CI, other): jobs for lint, types, tests (with service containers), build, security, container build; caching; matrix; required checks; concurrency cancel; least-privilege `permissions` |
| CD & hosting | Where it runs (Fly, Railway, Render, Vercel, Cloudflare, AWS/GCP/Azure, VPS, Kubernetes, app stores, package registry); deploy trigger; preview environments; rollbacks; zero-downtime migrations |
| Environments | dev / staging / prod; config per environment; promotion path |
| Secrets & config | Where secrets live (CI secrets, cloud secret manager, SOPS, 1Password/Doppler); `.env` handling; never in git; config validation at startup |
| Observability | Structured logging, error tracking (Sentry), metrics/tracing (OpenTelemetry), uptime/health endpoints, alerting |
| IaC | Terraform/OpenTofu/Pulumi/CDK/none. State backend |
| Dependency updates | Renovate or Dependabot, grouping and schedule, automerge policy for patch updates |
| Domain, TLS, DNS, email DNS (SPF/DKIM) | Only if public |

## Round 6: Collaboration & AI

| Topic | Ask / decide |
|---|---|
| Forge & workflow | GitHub/GitLab/other; trunk-based vs. PR flow; branch naming; branch protection; required reviews; merge strategy (squash) |
| Repo files | `.gitignore`, `.gitattributes`, `.editorconfig`, `CODEOWNERS`, PR template, issue templates, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (public), `LICENSE` |
| Documentation | README structure, `docs/` layout, ADRs (`docs/adr/`) for decisions made here, API docs generation, architecture diagram (Mermaid), changelog |
| Claude setup | `CLAUDE.md` (commands, architecture, conventions, gotchas), `.claude/settings.json` permissions (allow safe test/lint commands, deny destructive ones), `.claude/rules/`, MCP servers (docs, DB, browser), hooks (format on edit) |
| Harness | Offer `chriha/claude-plugins`; see the skill for the conditions and the flow |
| Maintenance | Who triages issues; support policy; deprecation policy (libraries) |

## Final catch-all

"Anything else I should know: must-haves, deal-breakers, past pain, things you want to try, things to avoid?"

## Questions worth asking that people forget

- "What will break first if this succeeds?" (scale), "what will hurt most if it fails?" (data loss, security)
- Who else will touch this code (contractors, community)? Drives docs and conventions.
- Is there an existing system, data or API this must integrate with or migrate from?
- Deployment constraints: company cloud, air-gapped, region, existing CI?
- Licences of dependencies (copyleft constraints for commercial use)
- What does the first week of development look like? Make the skeleton remove friction for exactly that.

## Update mode (existing project)

Used by `/project:update`. Same rounds, but only for chosen gaps, and every question starts from what exists:
- State what was detected ("You use Prettier and Vitest; no linter") before asking, and make the recommendation fit it.
- Prefer extending the current tool over swapping it; offer a swap only as a non-default option with its concrete cost.
- Match existing conventions (naming, layout, script names, commit style) instead of imposing the wizard's defaults.
- Skip Round 1-2 questions that detection already answers (language, framework, package manager, layout).

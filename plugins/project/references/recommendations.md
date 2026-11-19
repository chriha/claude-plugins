# Recommendation heuristics

Use when the user says "not sure", or to pick the first (recommended) option. These are **defaults, not dogma**: bend them to
the user's skills, constraints and goals, and always state the deciding factor. Training data is stale, so verify versions and
maintenance status on the web before recommending anything fast-moving.

## Decision order

1. **Existing skills and constraints win** (team knows X, employer mandates Y, hosting only supports Z).
2. **Fit to the problem**: CPU-bound, I/O-bound, real-time, data-heavy, UI-heavy, embedded, scripting.
3. **Maintainability**: static typing, mature ecosystem, stable APIs, readable by the next person.
4. **Time to value** for the stated timeline; don't over-engineer a prototype.
5. **Operational simplicity**: fewer moving parts, fewer services, cheaper to run.
6. **AI-assistant familiarity**: popular, well-documented stacks yield better Claude output; mention it when it tips a close call.

## Language by workload

| Workload | Default | Consider |
|---|---|---|
| Web app / SaaS, small team | TypeScript (full-stack) or the framework language the team knows (PHP/Laravel, Ruby/Rails, Python/Django) | Go backend + TS frontend when you want a single static binary and strong concurrency |
| Rapid CRUD / admin / content | Laravel, Rails, Django (batteries included) | Next.js if the team is JS-only |
| High-throughput API / network services / infra tooling | Go | Rust (when latency/memory are critical or correctness is paramount), Java/Kotlin (JVM shops), C# |
| Systems, embedded, perf-critical, WASM | Rust | C++/Zig (only when constrained by an existing ecosystem) |
| CLI tools | Go (single binary, easy distribution) or Rust; TypeScript/Python when the audience already has the runtime | |
| Data / ML / scripting / automation | Python (uv, ruff, pyright/mypy) | Rust/Polars for heavy pipelines; SQL + dbt for analytics |
| Mobile cross-platform | Flutter or React Native (Expo) | Native Swift/Kotlin when platform features dominate |
| Enterprise / large orgs | Java/Kotlin (Spring) or C# (.NET) | |
| Realtime / fault-tolerant messaging | Elixir (Phoenix) | Go, Node |
| Libraries/SDKs | The language of the primary consumers; TypeScript with generated types for JS | |

Always enable the **strictest practical typing** (TS `strict`, Python type hints + checker, PHP static analysis level, Go vet+staticcheck).

## Framework quick picks

- **TS full-stack**: Next.js (largest ecosystem), SvelteKit / Nuxt / Remix-React Router (lighter), Astro (content sites).
  API-only: Fastify or Hono; NestJS when you want enforced structure.
- **Python**: FastAPI (APIs, typing, OpenAPI), Django (full-featured, admin), Flask only for tiny services.
- **PHP**: Laravel (default). **Ruby**: Rails. **Go**: standard library + chi, or Echo/Gin; Connect/gRPC for service RPC.
- **Java/Kotlin**: Spring Boot, Ktor. **C#**: ASP.NET Core. **Rust**: Axum. **Elixir**: Phoenix.
- **Frontend**: React (ecosystem) vs. Svelte/Vue (simplicity). Tailwind + a headless/component library (shadcn/ui, Radix).
  Server state: TanStack Query. Forms/validation: schema lib (Zod/Valibot).
- Prefer the **framework's own conventions and generators** over custom structure.

## Architecture

- **Default: modular monolith** with clear module boundaries and one deployable. Split into services only for independent
  scaling, team autonomy at real scale, or distinct runtime needs, never "for future scale".
- Layering: transport (HTTP/CLI) → application/use cases → domain → infrastructure (DB, external APIs). Dependencies point
  inward. Don't add hexagonal ceremony to a simple CRUD app; do add it where there's real domain logic or many integrations.
- Enforce boundaries with tooling (import-lint rules, `deptrac`, `import-linter`, `dependency-cruiser`, Go internal packages).
- Serverless/edge: bursty or low-traffic workloads, small teams that want no ops; beware lock-in and cold starts.
- Event-driven/CQRS/event sourcing: only with an audit/replay/high-fan-out requirement.
- Record the choice and its rationale as an ADR.

## Database

| Need | Pick |
|---|---|
| General purpose, relational, transactions | **PostgreSQL** (default; JSONB, full-text, pgvector, extensions) |
| Embedded, single-user, CLI, edge, tiny apps | SQLite (WAL mode; Litestream/Turso if replication needed) |
| Highly variable documents, simple access by key | MongoDB or DynamoDB (justify) |
| Cache, rate limit, ephemeral, queues | Redis / Valkey |
| Time series / metrics | TimescaleDB, ClickHouse for analytics-scale |
| Graph-heavy | Postgres first; Neo4j when traversals dominate |
| Search | Postgres FTS → Meilisearch/Typesense → OpenSearch |
| Analytics warehouse | DuckDB (small), BigQuery/Snowflake/ClickHouse (large) |

Default to **one Postgres** for relational data, jobs (where the framework supports it), and vector search until a measured
reason says otherwise. Fewer services = less ops.

## Testing & static analysis defaults

- Pyramid: many fast unit tests, integration tests against a real DB (containers), a few e2e smoke tests of critical paths.
- Runners: Vitest/Jest (TS), pytest, PHPUnit/Pest, `go test` (+ testify optional), cargo test/nextest, JUnit5.
- e2e: Playwright. API contract: OpenAPI + schemathesis or similar.
- Static: TS `tsc --strict` + ESLint/Biome; Python ruff + pyright/mypy; PHP PHPStan/Larastan (level 6+ new projects, max if greenfield) + Pint;
  Go `go vet` + golangci-lint (staticcheck); Rust clippy `-D warnings` + rustfmt; Java SpotBugs/Error Prone.
- Greenfield projects can start strict; strictness is cheap now and expensive later.

## Containers & CI defaults

- Docker: multi-stage, pinned digests/tags, non-root user, healthcheck, `.dockerignore`, compose with app + DB + cache + mail catcher.
  Skip Docker for pure libraries and simple CLIs unless needed for reproducible CI.
- CI: GitHub Actions if on GitHub. Jobs: lint, typecheck/static, test (service containers), build, security; cache dependencies;
  `concurrency` cancel-in-progress; minimal `permissions`; pin third-party actions to a major (or SHA for high-security).
  Make the same commands runnable locally via the task runner so CI = `make ci`.
- Renovate or Dependabot on from day one. Secret scanning on.

## Hosting rule of thumb

- Solo/small + web: Fly.io, Railway, Render, or Vercel/Cloudflare for frontends and edge.
- Need control or cheap at scale: a VPS with Docker + Caddy; Kubernetes only with a platform team.
- Enterprise or compliance: the company's cloud (AWS/GCP/Azure) with IaC.
- Libraries: package registry + GitHub Releases. Mobile: store pipelines (EAS, Fastlane).

## Claude/harness recommendation

- Recommend `chriha/claude-plugins` if: iterative multi-session development with Claude, tickets on GitHub/GitLab/Linear,
  desire for guardrails (no force-push, drafts only) and a plan → implement → review loop.
- Skip if: throwaway prototype, one-shot script, or the user doesn't use an issue tracker/PR flow.
- Packs exist for Laravel and Go; otherwise `stack: none` with explicit commands.
- Regardless: always write a good `CLAUDE.md` (commands, architecture, conventions) and a conservative `.claude/settings.json`.

## When asked "why not X?"

Give the honest trade-off in 2-3 lines. Never pretend a choice is free.

# tour

Status: in development. Nothing works yet.

Guided review of a GitLab or GitHub MR/PR, human or AI authored. `/tour:review <id|url>` will group the change into chapters,
explain each one, and open a local web UI. The goal is that the reviewer understands the change. It is not a bug hunter
(`/harness:review` and `/code-review` do that), never runs automatically and never posts comments without an explicit click.

Planned skills: `/tour:review` (model `opus`), `/tour:clean` (model `haiku`).

The plugin stands alone: it does not need `harness`; shared code is copied into `bin/`.

## Helpers (`bin/`)

- `tour-fetch <id|url> [--no-open]`: detects the platform (`gh` or `glab`), fetches the MR/PR metadata and head ref, creates a detached worktree at the head SHA and writes `meta.json`, `diff.patch` and `atoms.json` (one atom per `git diff -U0` hunk) to `${CLAUDE_PLUGIN_DATA:-~/.claude/tour}/<host>/<project-path>/<iid>/<head-sha>/`. Reports `cached: true` when `tour.json` already exists for that head SHA.
- `tour-drift <data-dir>`: deterministic drift flags (new dependency, new migration, changed route/config/env keys, new top-level dir) as the `drift` array of the tour schema. No tokens.

Tests: `bash plugins/tour/tests/run.sh` (needs git and jq; `gh`/`glab` are stubbed, no network).

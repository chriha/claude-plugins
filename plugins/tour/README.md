# tour

Status: in development. Nothing works yet.

Guided review of a GitLab or GitHub MR/PR, human or AI authored. `/tour:review <id|url>` will group the change into chapters,
explain each one, and open a local web UI. The goal is that the reviewer understands the change. It is not a bug hunter
(`/harness:review` and `/code-review` do that), never runs automatically and never posts comments without an explicit click.

Planned skills: `/tour:review` (model `opus`), `/tour:clean` (model `haiku`).

The plugin stands alone: it does not need `harness`; shared code is copied into `bin/`.

## Contract

`references/tour-schema.md` defines `tour.json`. `bin/tour-validate <tour.json> <atoms.json>` checks it (needs `jq`), including that every diff atom is assigned exactly once. `fixtures/` holds valid example tours for UI work. Tests: `bash plugins/tour/tests/run.sh` (the server cases need node and curl).

## Viewing a tour

`bin/tour-serve <data-dir> [--port N] [--worktree <dir>] [--no-open]` serves the read-only UI for a cached tour (`<data-dir>` holds `tour.json`, `atoms.json` and `worktree/`, as written by `tour-fetch`). Needs node >= 18, no npm packages. It binds `127.0.0.1` on a random free port, prints a URL with a per-run token (every request needs it), opens the browser and runs until stopped. Progress and "understood" marks are saved to `state.json` beside `tour.json`. Keys: `j`/`k` blocks, `n`/`p` chapters, `u` mark understood. highlight.js and Mermaid load from cdnjs with pinned versions; the tour reads fine without them. To try it on a fixture: copy `fixtures/tour.full.json` to `<dir>/tour.json` and `fixtures/atoms.json` to `<dir>/atoms.json`.

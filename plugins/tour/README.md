# tour

Status: in development. Nothing works yet.

Guided review of a GitLab or GitHub MR/PR, human or AI authored. `/tour:review <id|url>` will group the change into chapters,
explain each one, and open a local web UI. The goal is that the reviewer understands the change. It is not a bug hunter
(`/harness:review` and `/code-review` do that), never runs automatically and never posts comments without an explicit click.

Planned skills: `/tour:review` (model `opus`), `/tour:clean` (model `haiku`).

The plugin stands alone: it does not need `harness`; shared code is copied into `bin/`.

## Contract

`references/tour-schema.md` defines `tour.json`. `bin/tour-validate <tour.json> <atoms.json>` checks it (needs `jq`), including that every diff atom is assigned exactly once. `fixtures/` holds valid example tours for UI work. Tests: `bash plugins/tour/tests/run.sh`.

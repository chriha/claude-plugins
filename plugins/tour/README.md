# tour

Status: in development. Nothing works yet.

Guided review of a GitLab or GitHub MR/PR, human or AI authored. `/tour:review <id|url>` will group the change into chapters,
explain each one, and open a local web UI. The goal is that the reviewer understands the change. It is not a bug hunter
(`/harness:review` and `/code-review` do that), never runs automatically and never posts comments without an explicit click.

Planned skills: `/tour:review` (model `opus`), `/tour:clean` (model `haiku`).

The plugin stands alone: it does not need `harness`; shared code is copied into `bin/`.

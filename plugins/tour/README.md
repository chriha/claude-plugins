# tour

Status: in development. `/tour:review` works; `/tour:clean` is not written yet.

Guided review of a GitLab or GitHub MR/PR, human or AI authored. `/tour:review <id|url>` groups the change into chapters,
explain each one, and open a local web UI. The goal is that the reviewer understands the change. It is not a bug hunter
(`/harness:review` and `/code-review` do that), never runs automatically and never posts comments without an explicit click.

Skills: `/tour:review` (model `opus`), `/tour:clean` (model `haiku`, planned).

The plugin stands alone: it does not need `harness`; shared code is copied into `bin/`.

## `/tour:review <id|url> [--regenerate] [--no-open]`

You start it; nothing triggers it (no push, schedule or HEAD hook). It runs in your own Claude Code session, so it uses that session's auth.

1. `tour-fetch` fetches the change (GitHub via `gh`, GitLab via `glab`). When a tour for the same head SHA is already cached, the UI opens right away and **no tokens are spent**. `--regenerate` drops the cached `tour.json` and builds a new one. `--no-open` skips the browser and prints the `tour-serve` command instead.
2. It shows diff stats and a token estimate (heuristic: diff tokens x layer factor, as small/medium/large plus a number) per layer.
3. **Cost gate** (`AskUserQuestion`): you pick the optional layers before any tokens go into them. Base (chapters, reading order, what/why/impact) is always on, and drift flags are always included because they are deterministic and free.

   | Optional layer | Default | Adds |
   |---|---|---|
   | Deep context | off | callers/dependents per changed symbol (CodeGraph when `.codegraph/` exists, else grep) |
   | Active review | off | a teaser and 2-3 break-it probes per chapter, with a test snippet in the repo's framework |
   | Architecture delta | off | before/after graph as Mermaid source |
   | Rules check | off | flags against the repo's `CLAUDE.md` and `.claude/rules/*` |

   A skipped layer writes none of its fields and gets no exploration (0 tokens), and the UI shows nothing for it: each layer renders only when it is listed in `tour.json` `layers`. Chat is not part of generation.

   What the UI does with each layer, and what drives its cost:

   | Layer | In the UI | Cost driver |
   |---|---|---|
   | Deep context | callers/dependents under each `impact` entry | one caller lookup (CodeGraph or grep) per changed symbol |
   | Active review | per chapter: the `intent` teaser and a box "what do you expect to change, and where?"; the chapter opens on **Reveal**, atoms your prediction did not name are marked "not predicted", and the 2-3 break-it probes with their test snippet appear. Predictions are saved in `state.json` beside `tour.json` and never leave your machine | writing a teaser and probes (with snippets in the repo's test framework) for every chapter |
   | Architecture delta | before/after Mermaid graph on the landing page | one graph, but it needs a read of the touched modules |
   | Rules check | flags per block, quoting the rule and its source file | reading `CLAUDE.md` and `.claude/rules/*` once, then checking each block against them |
4. It writes `tour.json`, runs `tour-validate` and repairs what it lists (at most 2 repair rounds), then starts `tour-serve`.

Changes above about 2000 changed lines are generated in batches by directory and merged; above 10000 it suggests splitting the MR. Reading order and wording rules live in `references/writing-guide.md`; the eval cases are in `evals/` (`review-cost-gate-fix-loop`, `review-active-layer`).

## Helpers (`bin/`)

- `tour-fetch <id|url> [--no-open]`: detects the platform (`gh` or `glab`), fetches the MR/PR metadata and head ref, creates a detached worktree at the head SHA and writes `meta.json`, `diff.patch` and `atoms.json` (one atom per `git diff -U0` hunk) to `${CLAUDE_PLUGIN_DATA:-~/.claude/tour}/<host>/<project-path>/<iid>/<head-sha>/`. Reports `cached: true` when `tour.json` already exists for that head SHA.
- `tour-drift <data-dir>`: deterministic drift flags (new dependency, new migration, changed route/config/env keys, new top-level dir) as the `drift` array of the tour schema. No tokens.

Tests: `bash plugins/tour/tests/run.sh` (needs git and jq; `gh`/`glab` are stubbed, no network; the server cases also need node and curl).

## Contract

`references/tour-schema.md` defines `tour.json`. `bin/tour-validate <tour.json> <atoms.json>` checks it (needs `jq`), including that every diff atom is assigned exactly once. `fixtures/` holds valid example tours for UI work.

## Viewing a tour

`bin/tour-serve <data-dir> [--port N] [--worktree <dir>] [--no-open]` serves the read-only UI for a cached tour (`<data-dir>` holds `tour.json`, `atoms.json` and `worktree/`, as written by `tour-fetch`). Needs node >= 18, no npm packages. It binds `127.0.0.1` on a random free port, prints a URL with a per-run token (every request needs it), opens the browser and runs until stopped. Progress and "understood" marks are saved to `state.json` beside `tour.json`. Keys: `j`/`k` blocks, `n`/`p` chapters, `u` mark understood. highlight.js and Mermaid load from cdnjs with pinned versions; the tour reads fine without them. To try it on a fixture: copy `fixtures/tour.full.json` to `<dir>/tour.json` and `fixtures/atoms.json` to `<dir>/atoms.json`.

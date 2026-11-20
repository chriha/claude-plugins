# tour

Status: in development. `/tour:review` and `/tour:clean` work.

Guided review of a GitLab or GitHub MR/PR, human or AI authored. `/tour:review <id|url>` groups the change into chapters,
explain each one, and open a local web UI. The goal is that the reviewer understands the change. It is not a bug hunter
(`/harness:review` and `/code-review` do that), never runs automatically and never posts comments without an explicit click.

Skills: `/tour:review` (model `opus`), `/tour:clean` (model `haiku`).

The plugin stands alone: it does not need `harness`; shared code is copied into `bin/`.

## `/tour:review <id|url> [--regenerate] [--no-open]`

You start it; nothing triggers it (no push, schedule or HEAD hook). It runs in your own Claude Code session, so it uses that session's auth.

1. `tour-fetch` fetches the change (GitHub via `gh`, GitLab via `glab`). When a tour for the same head SHA is already cached, the UI opens right away and **no tokens are spent**. `--regenerate` drops the cached `tour.json` and builds a new one. After a push (a new head SHA for a PR you toured before) it asks **New tour** or **Delta tour since `<old sha>`**, see "Delta tour" below. `--no-open` skips the browser and prints the `tour-serve` command instead.
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

Changes above about 2000 changed lines are generated in batches by directory and merged; above 10000 it suggests splitting the MR. Reading order and wording rules live in `references/writing-guide.md`; the eval cases are in `evals/` (`review-cost-gate-fix-loop`, `review-active-layer`, `review-delta-tour`).

## Helpers (`bin/`)

- `tour-fetch <id|url> [--no-open]`: detects the platform (`gh` or `glab`), fetches the MR/PR metadata and head ref, creates a detached worktree at the head SHA and writes `meta.json`, `diff.patch` and `atoms.json` (one atom per `git diff -U0` hunk) to `${CLAUDE_PLUGIN_DATA:-~/.claude/tour}/<host>/<project-path>/<iid>/<head-sha>/`. Reports `cached: true` when `tour.json` already exists for that head SHA.
- `tour-drift <data-dir>`: deterministic drift flags (new dependency, new migration, changed route/config/env keys, new top-level dir) as the `drift` array of the tour schema. No tokens.
- `tour-delta <old-data-dir> <new-data-dir>`: atom diff between two heads of the same MR/PR. An atom of the new head is unchanged when the old head has one with the same file and the same changed lines (hunk positions are ignored, so a push that only shifts lines changes nothing); all others are `changed` (the file was touched before) or `new`. Writes and prints `<new-data-dir>/delta.json`. No tokens.
- `tour-clean [--older-than <N>d|<N>w] [--yes]`: lists, and with `--yes` deletes, tours whose `meta.json`, `tour.json` and `state.json` are all older than the threshold (default 30d), with their git worktrees. Without `--yes` it deletes nothing.

Tests: `bash plugins/tour/tests/run.sh` (needs git and jq; `gh`/`glab` are stubbed, no network; the server cases also need node and curl).

## Delta tour (after a push)

`tour-fetch` reports `previous`: the newest other head of the same MR/PR that already has a `tour.json`. When it is set (and no `--regenerate`), `/tour:review` offers a **New tour** or a **Delta tour since `<old sha>`**. The delta tour runs `tour-delta`, then writes chapters for the changed atoms only. Every unchanged atom is listed in `mechanical` with the note "Unchanged since `<old sha>`: see the earlier tour", is not re-explained and spends no tokens; the schema is unchanged and `tour-validate` still checks coverage. If no atom changed (only line positions moved), the previous tour is opened instead.

## `/tour:clean [--older-than 30d]`

Prunes the data dir (`${CLAUDE_PLUGIN_DATA:-~/.claude/tour}`), which otherwise grows with every head you tour (a worktree each). **Default threshold: 30 days**, measured from the newest of a tour's `meta.json`, `tour.json` and `state.json`, so a tour you keep working in (progress, annotations and drafts update `state.json`) stays; one you only read does not. It shows what goes (age, size, directory) and the total, asks once, and only then deletes (`tour-clean --yes`): the head directory with its git worktree, and empty parent directories. Nothing newer than the threshold is touched.

## Contract

`references/tour-schema.md` defines `tour.json`. `bin/tour-validate <tour.json> <atoms.json>` checks it (needs `jq`), including that every diff atom is assigned exactly once. `fixtures/` holds valid example tours for UI work.

## Viewing a tour

`bin/tour-serve <data-dir> [--port N] [--worktree <dir>] [--no-open]` serves the UI for a cached tour (`<data-dir>` holds `tour.json`, `atoms.json` and `worktree/`, as written by `tour-fetch`). Needs node >= 18, no npm packages. It binds `127.0.0.1` on a random free port, prints a URL with a per-run token (every request needs it), opens the browser and runs until stopped. Progress, "understood" marks and ticked "check by hand" items are saved to `state.json` beside `tour.json`.

Layout: the sidebar lists the chapters (the current one expanded into its steps), every changed file and the drift signals; the main pane shows the overview, a chapter (one card per step: what, why with its source, its diffs) or a file; the inspector on the right has three tabs for the current step: **Context** (impact, callers), **Checks** (watch items, rules flags, break-it probes) and **Ask** (chat). A file can be split across chapters, so each file row lists the steps its hunks belong to, and the file view shows every hunk of that file with a link to its step, plus the whole file at the head SHA. Keys: `j`/`k` steps, `n`/`p` chapters, `u` mark understood, `c` comment, `⌘K` or `/` jump to a step or file. The UI loads no web fonts (IBM Plex Sans and JetBrains Mono when installed, system fonts otherwise). highlight.js and Mermaid load from cdnjs with pinned versions; the tour reads fine without them. To try it on a fixture: copy `fixtures/tour.full.json` to `<dir>/tour.json` and `fixtures/atoms.json` to `<dir>/atoms.json`.

## Comments

Click a line number (or press `c` for the first changed line of the current block) to draft a comment; the draft opens inline under that line, and the drawer (`Comments` in the bar) lists all drafts, with `Post` per draft and `Post all`. Drafts live in `state.json` (`drafts`). Nothing is posted without that click, and the tour never approves. The server is the only poster: it validates the draft against `atoms.json` and runs `bin/tour-post <data-dir> --path <file> [--old-path <file>] [--old-line N] [--new-line N]` (comment on stdin). GitHub gets a review comment (`gh api`, `side=RIGHT` for added and unchanged lines, `LEFT` for removed ones); GitLab gets a discussion with a DiffNote position built from the MR's `diff_refs` (`glab api --input`) and refuses when the MR head moved since the tour. A posted draft is marked with its note id and cannot be posted twice; a failed post keeps the draft and shows the CLI's error verbatim. Needs `jq` plus `gh` or `glab`.

## Chat

Each chapter has a chat in the inspector's **Ask** tab. It costs tokens only when you type, so it is not part of the cost gate. `POST /api/chat {chapter, message}` makes the server spawn `claude -p --output-format stream-json --verbose --include-partial-messages --tools Read,Grep,Glob --allowedTools Read,Grep,Glob [--resume <session>]` with the MR worktree as cwd and streams the reply to the panel as server-sent events. It uses the CLI login (no API key, no extra dependency) and the tools are read-only: no edits, no shell. The first message of a chapter carries the chapter and its atoms; the session id and the transcript are kept in `chat/<chapter>.json` in the data dir, so a reload (or a restarted server) resumes the conversation. It shares your subscription's rate limits: a CLI or rate-limit error is shown verbatim and not retried. `TOUR_CLAUDE_BIN` overrides the `claude` binary (tests).

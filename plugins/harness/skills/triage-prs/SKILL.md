---
name: triage-prs
description: Sort open PRs/MRs into AI-reviewable vs human-review-required lanes (labels review:ai / review:human) with a risk note per PR, one sub-agent each
argument-hint: "[pr# …]"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Agent, Bash(harness-*:*), Bash(jq:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*), Bash(git fetch:*), Bash(git rev-parse:*), Bash(gh pr:*), Bash(gh api:*), Bash(gh label:*), Bash(gh issue:*), Bash(glab mr:*), Bash(glab api:*), Bash(glab label:*), Bash(glab issue:*), mcp__linear, mcp__codegraph__codegraph_explore
---

Sort open PRs/MRs into two review lanes with the labels **`review:ai`** (small, isolated — an AI review may be enough) and
**`review:human`** (a human must review). One sub-agent per PR. Read-only on code; the only writes are the label and one note per PR.
Argument (optional): PR numbers to (re-)triage, bypassing the skip rules (`/harness:triage-prs 1861 1860`).

Operations (`list-prs`, `view-pr`, `pr-diff`, `pr-label`, `pr-ci-status`, `pr-notes`, `comment-pr`, `codeowners`, `read-ticket`, …) come
from the forge/tracker adapters named in `.claude/harness.md` § Tracker (`harness-resolve adapters/<name>.md`). No harness.md → say
"run `/harness:init` first" and stop. Report layout: `harness-resolve briefs/console-report.md` (header `━━ /harness:triage-prs ━━`).

## Step 1 — Labels
Create the two labels once when missing (`create-label` / the forge's label command): `review:ai` (green, "Small, isolated change.
AI review may be enough.") and `review:human` (red, "Touches shared behaviour. Human review required."). On GitLab the scoped form
`review::ai` / `review::human` is used when the project already has scoped labels; use one form consistently.

## Step 2 — Pick PRs
`list-prs` (open), keep those that are **not draft** and:
- have **no** `review:*` label → triage, or
- have `review:ai` but the head sha moved since the last triage (the newest note containing `<!-- harness-pr-triage sha=` via
  `pr-notes`; none → re-triage).

`review:human` is sticky — never re-triaged automatically (only via an explicit argument).

**CI gate:** per kept PR `pr-ci-status`. No pipeline/checks, a pipeline for an older sha, or one still running → skip it this run
("waiting on CI"); the next run picks it up. Pass the status to the agent. Nothing to do → say so and stop.

## Step 3 — Fan out
One **sonnet** sub-agent per PR, all in a single message (batches of 10), each with the prompt below (fill in `<pr>`, `<ci status>`,
`<adapter paths>`). Tell each: tools work, no exploratory calls, don't check out branches, don't approve, comment inline or push.

> Triage PR/MR <pr> of this repo. Read `CLAUDE.md` first. Fetch `view-pr` (title, description, sha, author, source branch) and
> `pr-diff`. Head CI status: `<ci status>`. Read the CODEOWNERS file (`codeowners` operation; none → no path trigger).
>
> **Ticket:** `ticket-of-pr`, then `read-ticket`. Never guess an id.
>
> Decide the lane. **`review:human` if ANY hard trigger matches** — no judgement, no exceptions:
> - CI `failed`.
> - No linked ticket, the ticket has no acceptance criteria, or the diff changes things outside the ticket's scope ("while I was here"
>   cleanups, changed defaults, loosened validation).
> - Mixes a refactor with a behaviour change — the diff must be either "no behaviour change" or "behaviour change + test". Say in the
>   note that it should be split.
> - Any changed file matches a CODEOWNERS rule.
> - Size: > 400 changed lines (excluding tests, lockfiles and harness.md `exclude_from_size`) or > 15 files.
> - Tests deleted, skipped, or assertions weakened; lint/arch-test exemptions or static-analysis baseline entries added.
> - Tests that can't fail: no assertions, asserting on a mock's own return value, or mocking the class under test.
> - Touches auth, permissions, tokens/secrets, payments, PII, raw SQL, queue/job retry or timeout config, scheduling, cache keys/TTL,
>   search-index mappings, infrastructure/CI config.
> - Backward-incompatible deploy: a changed serialized payload, event payload or schema, or code that stops using a column in the same
>   PR that drops it. Old and new code must run side by side.
> - Security smells: widened mass-assignment, an `authorize()` that always returns true on a non-public endpoint, unscoped queries,
>   raw SQL with interpolation.
> - Public API contract change: routes, response shape, API spec, events consumed elsewhere.
> - Data-mutating commands/backfills or anything irreversible in production.
> - Description empty, or the diff does something the title/description doesn't say.
> - Anything in harness.md § Review triggers (`harness-config section "Review triggers"`).
>
> No hard trigger → judge **blast radius**: `review:ai` only if the change is local (one feature/module, no shared service/trait/base
> behaviour changed for other callers), has tests covering the changed behaviour, and a wrong change would be caught by tests or be
> trivially reversible. Unsure → `review:human`.
>
> Also scan for **AI failure patterns** and list hits under risk hotspots (they don't force the lane): a new broad catch / swallowed
> error / `?.` added to silence one, a helper duplicating an existing one (grep for it), calls to methods that may not exist.
>
> Apply it: `pr-label` add `review:<lane>`, remove `review:<other>`; then `comment-pr` (general) with:
> ```
> **PR triage: `review:<lane>`** — <one-sentence reason>
> - <each hard trigger hit, or the blast-radius reasoning, max 5 bullets with file paths>
> - Review the tests first: <test files, and whether they cover the ticket's acceptance criteria>
> - Risk hotspots for the reviewer: <files/lines worth the closest look, incl. AI failure patterns>
> <!-- harness-pr-triage sha=<head sha> -->
> ```
> Return only: `<pr> <lane> — <reason>`.

## Step 4 — Report
Console layout of `briefs/console-report.md`. `VERDICT` e.g. `<n> need review · <n> AI-reviewable · <n> skipped`. **NEEDS YOU** = PRs in the
human lane (next action: review it) and any PR whose label or note could not be written; **DONE** = PRs in the AI lane, one line
each; **NO ACTION** = skipped PRs (draft / already triaged / waiting on CI) with the reason. `── details ──`: table of PR, title, lane, reason.

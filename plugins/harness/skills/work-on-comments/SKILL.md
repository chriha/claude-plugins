---
name: work-on-comments
description: Fetch the open review comments on this branch's PR, verify each against the code, then fix, push, reply and resolve them autonomously (or step by step with -i), and harvest the lessons into guardrails
argument-hint: "[-i | --interactive] [--quick-fix] [--dry-run]"
disable-model-invocation: true
model: sonnet
allowed-tools: Read, Grep, Glob, Agent, AskUserQuestion, Bash(harness-*:*), Bash(git branch:*), Bash(git log:*), Bash(git diff:*), Bash(git status:*), Bash(git add:*), Bash(git commit:*), Bash(git rev-parse:*), Bash(git push:*), Bash(git restore:*), Bash(git fetch:*), Bash(git pull --ff-only:*), Bash(git merge-base:*), Bash(git show:*), Bash(jq:*), Bash(gh pr:*), Bash(gh api:*), Bash(gh issue:*), mcp__codegraph__codegraph_explore, Bash(glab issue:*), Bash(glab mr:*), Bash(glab api:*), mcp__linear
---

Operations (`pr-of-branch`, `review-threads`, `reply-to-comment`, `resolve-thread`, …) come from the forge adapter named in
`.claude/harness.md` § Tracker (`harness-resolve adapters/<name>.md`). Project checks: harness.md § Commands (`test`, `static`, `format` = the **gates**).
`<default>` = default branch.

**Modes** (flags combine):
- **default** — autonomous: no questions, no approval stops. Fixes every Valid and Partly valid comment, pushes once, replies, resolves the fixed threads.
- **`-i` / `--interactive`** — approval stops (Steps 2–6 "interactive" notes): nothing is pushed, replied to or resolved without the human saying so.
- **`--quick-fix`** — fixes only 🟢 quick fixes; 🔴 complex comments are left untouched and listed under NEEDS YOU. Otherwise as default.
- **`--dry-run`** — writes nothing (no commit, push, reply, resolve, ticket): prints the Step 2 plan with the drafted replies, then the report, and stops.

**Step 1 — Fetch & categorize**

First `git fetch`; behind its upstream → `git pull --ff-only` (diverged → stop, NEEDS YOU). Record `<start>` = `git rev-parse HEAD`.
In parallel: current branch (`git branch --show-current`) and the branch diff (`git diff <default>...HEAD`). Then:
- `pr-of-branch` → open PR; none → say so and stop.
- `review-threads` (unresolved, with resolution state; page past 100) and general PR comments/reviews. A human comment asking for a change is open; ignore approvals and pure acknowledgements.

Keep only **unresolved** threads with human-authored notes (not the PR author replying to themselves, no bots/system notes). Keep outdated threads but say so.
Replies this skill posted start with `<!-- ai-reply -->` (Step 5). Per thread, by its **last** note:
- last note starts with `<!-- ai-reply -->` → skip (NO ACTION: already answered), unless a commit newer than that reply exists on the branch → treat as open again.
- last note is an `<!-- ai-reply -->` `Fixed in <sha>` / `Tracked as <ticket>` and the thread is still unresolved → the earlier resolve failed: only `resolve-thread` it (Step 5), no verification or fix.
No open comments and nothing to resolve → say so and stop.

**Verify first.** Give every comment a verdict by reading the code it references (and callers where the claim depends on them): one sonnet sub-agent per
comment in parallel (`model: "sonnet"`; `"opus"` for a complex or disputed one: design, concurrency, security or data-loss claims, or a thread with a back-and-forth), each returning a verdict with file:line evidence:
✅ **Valid** · ◐ **Partly valid** (say which part) · ❌ **Invalid** (code contradicts the claim) · ❓ **Unverifiable**.
Invalid/Unverifiable never trigger a code change: → 💬 Clarify with a drafted reply (cite evidence, or what's needed to verify).

Group the rest: 🟢 **Quick fix** (trivial, low risk; fixer `sonnet`) · 🔴 **Complex** (design/refactor, or Partly valid/disputed; fixer `opus`) · 💬 **Clarify**.
Then scan the diff for the *same class of issues* the reviewers flagged but missed elsewhere; add them as self-identified items (fixed, but no thread to reply to).

**Not fixed automatically — only for one of these reasons** (each is reported, never silently dropped):
1. Verdict Invalid or Unverifiable → reply with the evidence (Step 5); thread stays open.
2. The fix would contradict an acceptance criterion or adopt an option the ticket's `## Decision` rejected (`ticket-of-pr`, `read-ticket`) → reply citing it; thread stays open; NEEDS YOU.
3. A gate fails after the fix and is not quickly fixable (2 attempts) → `git restore` that fix's files (delete files it created), no commit, no reply; NEEDS YOU with the failing check.
Unclear intent is not a reason: the verdict step already sent it to Clarify.

**Step 2 — Plan.** Print: review status in a line; the categorized list (file:line, verdict + evidence, model, any not-fixed reason); one sentence per fix;
the drafted reply for each Invalid/Unverifiable. `--dry-run` → stop here (then the report).
Default / `--quick-fix`: go on without asking. Interactive: ask "Shall I work on all the quick fixes?".

**Step 3 — Fixes.**
- **Quick fixes** (all modes): each in a `sonnet` sub-agent, one focused Conventional Commit per fix (`harness-resolve briefs/git-rules.md`), gates clean before each commit; a gate failure → reason 3.
- **Complex** (default): an `opus` sub-agent (or the session if already opus) reads all relevant code, picks its own recommended approach (no choice stop), implements it, one commit, gates clean. `--quick-fix`: skip, list under NEEDS YOU.
- **Complex** (interactive): one at a time. `opus` presents 1–3 approaches with trade-offs and a recommendation; wait for a choice, implement, summarize, wait for confirmation before the next.
- Interactive: report when the quick fixes are done. Nothing is pushed and no thread is resolved or replied to without the human saying so.

**Step 4 — Check (default / `--quick-fix`, only if there are commits).** One fresh-context `opus` sub-agent (new, not a fork; read-only) gets
`git diff <start>..HEAD`, the commit log and the comments, and hunts for edge cases, logic bugs and security problems the fixes introduced.
Real findings → one extra commit, gates clean. Then run the gates once more on HEAD; any red → no push, no reply, no resolve: NEEDS YOU with the failing check.

**Step 5 — Push, reply, resolve (default / `--quick-fix`).**
1. Commits exist and gates are green → `git push` once (never force). A failed push → NEEDS YOU, and nothing below happens. No commits → skip the push, still do 2 and 3.
2. Reply (`reply-to-comment`) per thread; every body starts with the hidden line `<!-- ai-reply -->`:
   - fixed (Valid/Partly valid) → `Fixed in <short sha of the fix commit>`; then `resolve-thread`.
   - Invalid/Unverifiable → the drafted reply with evidence; thread stays open.
   - reason 2 → the reply citing the criterion/decision; thread stays open.
   - reason 3 and `--quick-fix`-skipped complex → no reply.
3. Threads found in Step 1 with an earlier `Fixed in` / `Tracked as` reply → `resolve-thread` only.
Interactive: `reply-to-comment` / `resolve-thread` / push only on request; clarifications one at a time — quote the comment and verdict, give context (what the code does, symbols with
line numbers), show the drafted reply and ask how to respond; continue until all are addressed.

**Step 6 — Harvest.** Classify and group (`harness-resolve briefs/tickets.md`, "Harness harvest", steps 1–2) over every comment fixed or answered this run, incl. the
self-identified ones. Default / `--quick-fix`: skip the confirm step, file nothing, list the candidate patterns under `Also:`. Interactive: run the full harvest (confirm once, as today).
Skip if none were resolved. `--dry-run`: skip.

End with the console layout of `harness-resolve briefs/console-report.md` (header `━━ /harness:work-on-comments · <pr> ━━`): NEEDS YOU = open threads, not-fixed reasons 2–3,
untouched complex comments (`--quick-fix`), gate/push failures and clarifications waiting for the human, DONE = fixed and answered comments (with the commit sha), NO ACTION = skipped
`<!-- ai-reply -->` threads and nothing-to-do.

# Harness conventions (read this before writing or editing any skill, brief or script)

## Layers — project always wins
1. **Plugin defaults** (this dir): `skills/`, `briefs/`, `adapters/`, `bin/`, `packs/`, `templates/`, `agents/`, `hooks/` (the last two are not overridable).
2. **Project config** `<repo>/.claude/harness.md` — facts about the project (commands, triggers, forge, tracker). Created once by `/harness:init`; owned by the project.
3. **Project overrides** `<repo>/.claude/harness/<same relative path as in the plugin>` — a file here **replaces** the plugin file of the same path (e.g. `briefs/implementer.md`, `briefs/review-criteria.md`, `adapters/github.md`). Nothing is merged; copy the default and edit it only when config is not enough.

Resolution is always done with the `harness-resolve` command (in `bin/`, on PATH):
`harness-resolve briefs/implementer.md` prints the absolute path of the override if it exists, else the plugin default.
Skills and briefs never hardcode `${CLAUDE_PLUGIN_ROOT}` paths for files that can be overridden; they say "resolve `briefs/x.md`".
Sub-agent prompts get the **resolved absolute path** ("Read and follow `<abs path>`").

## harness.md (project config, markdown; scripts read `key: value` lines — `harness-config key` drops a trailing `<!-- -->` and wrapping backticks)
Sections the briefs refer to by name — keep these headings:
- `## Tracker` — `tracker: github|gitlab|linear` · `forge: github|gitlab` (a PR is an MR on GitLab) · adapter names resolve to `adapters/<name>.md`; labels in use; priority label scheme. Supported combinations: any tracker with any forge (`linear` needs `linear_team:` and, for scripts, `LINEAR_API_KEY`).
- `## Commands` — `test:`, `static:` (lint/static analysis, may be empty), `format:` (check cmd, must print nothing/exit 0), `build:`, `setup-worktree:` (run once in a fresh worktree, may be empty), `test-affected:` (how to run a subset; `{files}` placeholder).
- `## Scripts` — `red_check_test_cmd:` (`{files}`/`{packages}` placeholders), `test_file_glob:` (git pathspec, e.g. `**/*_test.go`), `exclude_from_size:` (pathspecs excluded from the changed-line count).
- `## Branch & commits` — branch types, branch regex, commit types, max subject length, whether a ticket id goes in the commit subject, `Co-Authored-By` line.
- `## Plan-first triggers` — project-specific list that extends the generic gate in `briefs/implementer.md`.
- `## Self-check` — project-specific "no X" list run before each commit.
- `## Test conventions` — what a good test looks like here (feeds `review-criteria.md` "Test quality").
- `## Review triggers` — extra "a human must review this PR" cases for `/harness:triage-prs` (CODEOWNERS paths count already).
- `## Never` — hard rules (deps changes need approval, no migrations without plan, ...).
Missing section = generic defaults apply. The briefs say "per harness.md § <Section>".

## Tracker / forge adapters
Briefs and skills speak in **operations**, never in CLI strings (shipped adapters: `github`, `gitlab`, `linear`). `adapters/<name>.md` maps each operation to exact commands:
read-ticket, list-tickets, list-triage, edit-description-section, comment, add/remove-label, assign-me, set-priority, accept-triage, close-not-planned, close-duplicate, create-ticket, blockers (read/add), list-prs, create-draft-pr, pr-diff, pr-comments (inline + general), edit-pr-base, pr-state-of-branch, pr-label, pr-ci-status, pr-notes, codeowners, closing-keyword, ticket-id regex, collision-search.
`adapters/_template.md` lists every operation to fill in for a new platform.

## Paths
`<repo>` main checkout (absolute) · `<wt>` = `<repo>/.user/worktrees/issue-<id>` · `<report>` = `<repo>/.user/reports/issue-<id>.md` · run log `<repo>/.user/runs/<YYYY-MM-DD-HHMM>.md` (one per `/harness:work` run) · cleaned tickets' reports move to `<repo>/.user/reports/archive/issue-<id>-<YYYY-MM-DD>.md` · `harness-sync` prunes `.user/runs/` and `.user/reports/archive/` files older than 90 days · `.user/` is gitignored (init ensures it).

## Hard rules are enforced in code
A brief states a rule; a hard rule (one that must never be broken) also gets a check, so a violating call is refused, not trusted
not to happen:
- **`hooks/hooks.json` → `bin/harness-guard`** (PreToolUse on Bash/Edit/Write/MultiEdit/NotebookEdit). Scope: calls from a
  `harness:*` agent (`agent_type` in the hook input; Claude Code sets it for sub-agent calls only) or targeting/running under
  `<repo>/.user/worktrees/`; everything else passes untouched. Refuses force-push (any flag form, `+refspec`), `gh pr merge|ready`,
  `gh pr review --approve`, `glab mr merge|approve|update --ready`, merge/approve API endpoints (`gh api`/`glab api`), non-draft `gh pr create` / `glab mr create`, `git commit --no-verify|-n`, Edit/Write on lockfiles and `go.mod`/`go.sum`, writes under
  `.user/worktrees/_main`. Each deny reason names the rule and its brief — keep them in step when a brief changes. Text matching,
  not a sandbox. Tests: `tests/run.sh`.
- **`hooks/hooks.json` → `bin/harness-credential-guard`** (PreToolUse on Bash/Monitor/Read/Grep/Glob): same scope as `harness-guard`; denies
  reads of `~/.ssh` and `~/.aws/{credentials,sso,cli/cache}` (path-resolved for Read/Grep/Glob, command text for Bash). `--always` checks every
  call of every session — wired by the project in its own settings (`/harness:init` offers it). Best effort, not containment.
- **Plugin agents `agents/{triager,implementer,verifier}.md`** — `/harness:work` spawns `harness:<role>`, never `general-purpose`.
  The read-only roles use `disallowedTools: Edit, Write, MultiEdit, NotebookEdit` (not `tools:`, so MCP tools stay); they keep Bash
  for tracker writes and focused test runs. The agent body only points at the brief — the brief (resolved, overridable) is the
  source of truth.
- **Settings `deny`** in `templates/settings.base.json` — backstop for never force-push / merge / mark ready; `/harness:init`
  unions it into `.claude/settings.json`, `/harness:doctor` flags missing entries. It applies to interactive sessions too, and
  prefix patterns can't catch combined flags (`-uf`) — the guard does.
- A new hard rule → add it to the brief **and** to `harness-guard` with a test (and to `deny` when a permission pattern can express it).

## Models and effort
One scheme for every agent and skill; `harness-candidates`, the triager, `/harness:work`, the skills' `model:` frontmatter, the
implementer brief (§ Consults) and `harness-retro` follow it. There is no per-project model key.
- **Triager and verifier** (`agents/{triager,verifier}.md`, spawned with `model: "sonnet"`) run on sonnet — haiku is too weak for
  gating and verification.
- **Implementer** — the triage row carries its model. `bin/harness-candidates` defaults every row to **sonnet**; the triager
  upgrades a row to **opus** only for a clearly cross-module ticket (the ticket or its `## Plan` / `## Touches` spans several
  modules or layers, or changes a shared interface). Plan-approved alone does not pick opus. `/harness:work` spawns an opus
  implementer with `effort: "high"` and a sonnet implementer at the default effort (no `effort`). The `checks-red` retry on opus
  also runs with `effort: "high"`.
- All sub-agents keep their plugin agent type (`harness:triager|implementer|verifier`) and `run_in_background: true`.
- **Skills** declare `model:` in their frontmatter: `work`, `review`, `work-on-comments`, `triage`, `triage-prs`, `init`,
  `doctor`, `harness-retro` → **sonnet**; `ticket`, `arch-loop` → **opus**; `verify` → **opus** with `effort: high`.
  `init`, `doctor` and `harness-retro` are mechanical file/CLI work and report formatting; `arch-loop` judges architecture drift.
- `/harness:ticket`'s plan-grill step spawns one fresh read-only opus sub-agent (not a fork); plan optimisation keeps naming
  haiku/sonnet/opus per slice.
- `/harness:work-on-comments`: one sonnet sub-agent per comment (opus for a complex or disputed one), sonnet fixers for quick fixes,
  opus fixers for complex ones, and a fresh opus check over the commits it made.
- `/harness:review`: haiku lists the relevant CLAUDE.md paths, sonnet reviewers and validators, one opus re-validation over
  confirmed-low and hot-path findings.

## Implementer consults
The implementer session is the only agent that writes code. It calls short-lived consult sub-agents; each prompt carries the
ticket, the specific question, the relevant findings and the diff — never the session transcript — and the brief fixes the reply
format. A session that already runs on opus answers the opus consults itself, no spawn.
- **Haiku auditor** — mechanical, checkable work only; replies are lists of `file:line`, never conclusions: the Self-check audits
  over the diff (functions that don't exist, duplicated helpers, swallowed errors, unquoted shell/SQL), caller and sibling-pattern
  lookups, the scope/size check (files the ticket doesn't name, the ~400-line limit). Run in parallel in one message. Gate
  exploration stays with the session.
- **Opus advisor** — at four fixed triggers only, never "when it feels big":
  1. **Gate** — a plan-first trigger is uncertain → replies `just-solve` | `plan` | `needs-info` + one line why.
  2. **Plan** — writes the `## Plan` block.
  3. **Stuck fix** — after the 2nd failed attempt of the 3-attempt fix budget → a diagnosis from the failing output and the diff.
     The `checks-red` retry respawns the implementer on opus only when this consult already ran (its RESULT carries
     `· consult: stuck-fix` after the class).
  4. **Sign-off** — gets both reviewers' merged findings and the diff, drops false positives among the `/code-review` findings
     (the rules-review agent's are already validated), adds misses, and does one short re-check after the fix commit. Opus when changed lines > 200 (the
     review step's count after `exclude_from_size`, same cutoff as the `/code-review` level) or the ticket is plan-approved;
     sonnet otherwise.
- **Rules review** (implementer Review step, not a consult): one fresh read-only **opus** sub-agent applies
  `briefs/review-criteria.md` including Validation — one sonnet validator per candidate (`confirmed-high | confirmed-low |
  dropped`), the opus agent itself re-validates `confirmed-low` and hot-path candidates — and replies with the surviving findings
  plus a `counts:` line. `/code-review` runs in parallel in the same message. The sign-off never re-validates the rules-review
  findings, so no finding is validated twice.
- The report's `## Review` records each consult (role, model, trigger) and its token use next to the rules-review agent's `counts:` line and
  tokens; `harness-retro` counts them.

## Behaviour is checked by evals
`tests/run.sh` covers `bin/`; `evals/<case>/case.yaml` (`claude plugin eval`) covers how agents behave under a brief/skill.
- **A brief/skill behaviour change updates or adds an eval case**; run it before and after the change and compare with
  `bin/harness-eval-diff` (per case `prev → new`, `DROP` on a fall). A new case is checked once by hand: planting a regression
  in the brief it guards lowers its score (note it in the PR).
- Cases run offline: `case.yaml` names `scaffold.sh`, which calls `_shared/scaffold.sh` — throwaway repo with a bare `origin`,
  case `fixtures/`, a fake `gh` first on PATH (answers adapter operations from fixture JSON, logs calls to `.harness-eval/gh.log`),
  git ref logs (`git.log`, `origin.log`); optional `setup.sh` for extra state. Graders score 0–1 from those logs and the reply.
- Run: `claude plugin eval plugins/harness [--case '<glob>'] --scaffold --ablation none --allow-tools Bash Write Edit --max-cost-usd <usd>`.
  Always cap the cost. `--ablation none` because the scaffold puts the plugin's `bin/` on PATH for both arms (a no-plugin arm
  measures nothing). Results land in `evals/results/` (gitignored).

## Permission rules (allow / deny patterns in settings and `allowed-tools`)
Verified against `claude -p`; re-probe after a Claude Code upgrade. `/harness:doctor` flags the first three.
1. **A deny always beats an allow.** A scoped allow cannot carve an exception out of a broader deny: with deny `Bash(git -C:*)`, the allow
   `Bash(git -C /wt diff:*)` never runs.
2. **A trailing `:*` matches the prefix up to a word boundary** (whitespace or end of command): `Bash(gh:*)` matches `gh pr list`, not `ghost`.
3. **A `:*` after a mid-pattern `*` never matches.** `Bash(git -C * push:*)` blocks nothing; write `Bash(git -C * push*)`.
4. **Don't rely on per-verb denies under a broad allow.** Under `Bash(git -C:*)`, `git -C /wt -c alias.p=push p` slips past a `push` deny. Deny the
   broad prefix, or narrow the allow.
5. **A deny on a script path blocks only that exact way of calling it** (`scripts/x.sh` ≠ `bash scripts/x.sh` ≠ an absolute path ≠ a child process).
   To stop a script entirely make it refuse to start (e.g. on an env var a guard sets); keep the deny as documentation.
6. Hard rules go into `harness-guard` (it parses the command), not into a pile of deny patterns.

## Console report
`briefs/console-report.md` is the one report layout (`VERDICT` / `NEEDS YOU` / `READY FOR REVIEW` / `NO ACTION` / `Also:` / `── details ──`) for
`work`, `review`, `triage-prs` and `work-on-comments`: every outcome maps to exactly one section, anything needing a human action first.

## Review markers (PR/MR comments)
`<!-- ai-review -->` — first line of every inline finding posted by `harness-inline-note` (`harness-retro` counts a discussion as an AI finding
only when its first note starts with it). `<!-- harness-review -->` + `<!-- harness-review-sha: <full head sha> -->` — end of every comment
`/harness:review --comment` posts: they identify prior reviews (settled vs new commits) and stop a second review of the same commit.
`<!-- harness-pr-triage sha=<sha> -->` — the note `/harness:triage-prs` leaves, so a moved head re-triages.

## Forge notes
`gh`/`glab` run against `origin`. PR = MR, PR number = `iid`. Scripts take the forge from `forge:` (`harness-sync`, `harness-worktree`, `harness-check-pr`,
`harness-inline-note`, `harness-candidates`); `harness-candidates` also takes `tracker:` (github | gitlab | linear) — ids are strings (`12`, `ENG-12`).
A new platform = a new adapter file plus a backend class in `harness-candidates` and a branch in the forge switches.

## Style
Terse imperative briefs, no prose padding. Orchestrators stay thin (route only). Sub-agent final reply = a single RESULT block/line defined in its brief.
Skills are named without prefix; the plugin namespace gives `/harness:<name>`.

## Optional harness.md keys/sections used by specific skills
`## Verify` (verify, see its header) · `## Ratchets` (`name: command printing a number`, harness-retro) · `arch_test:` (arch-loop) ·
`metrics_doc:` (default `docs/harness-metrics.md`) · `sentry: true`. Optional project file `.claude/harness/architecture-domains.md`.

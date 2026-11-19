# harness

One Claude Code plugin that gives any repo the same ticket → plan → implement → review pipeline, without copying files between projects.

## Install (once, user scope)

```
/plugin marketplace add chriha/claude-plugins
/plugin install harness@chriha
```
Or from a shell: `claude plugin marketplace add chriha/claude-plugins && claude plugin install harness@chriha`.

Update with `/plugin marketplace update chriha` followed by `claude plugin update harness`. There's no `version` in `plugin.json`,
so updates track commit SHAs. Add a `version` there if you'd rather release explicitly.

**Developing the plugin:** to have local edits apply at the next session start or `/reload-plugins`, add your clone as the marketplace
instead: `/plugin marketplace add /path/to/claude-plugins`.

## Add to a project

`/harness:init` in the repo — detects stack/forge/tracker, writes `.claude/harness.md`, copies the stack pack once, merges permissions.
That is the only per-project footprint besides optional overrides.

## Layers (project always wins)

| Layer | Where | Updated by |
|---|---|---|
| Plugin defaults: skills, briefs, adapters, scripts (`bin/`) | `plugins/harness/` in this repo | `git pull` / plugin update — **all projects at once** |
| Project config | `<repo>/.claude/harness.md` | you; facts only (commands, triggers, forge) |
| Project override | `<repo>/.claude/harness/<same path as in the plugin>` | you; replaces the plugin file wholesale |
| Pack files copied once (rules, githooks) | `<repo>/.claude/rules`, `.githooks` | you; `/harness:doctor` shows drift from upstream |

Skills and briefs resolve every overridable file through `harness-resolve`, so an override needs no registration.

## Skills

`init` · `doctor` · `ticket` · `triage` · `work` · `review` · `triage-prs` · `work-on-comments` · `verify` · `harness-retro` · `arch-loop`
Invoke as `/harness:<name>`.

`work-on-comments [-i] [--quick-fix] [--dry-run]` fixes the open review comments on the branch's PR on its own: verifies each, commits a fix per comment, runs the
gates, pushes once, replies `Fixed in <sha>` and resolves the fixed threads (replies carry a hidden `<!-- ai-reply -->` marker). Invalid comments get an evidence
reply and stay open. `-i` asks before every step and pushes or posts nothing unasked; `--quick-fix` skips complex comments; `--dry-run` only prints the plan.

## Models

Triager and verifier run on sonnet. The triage row carries the implementer model: sonnet by default, opus (spawned with
`effort: "high"`) for a clearly cross-module ticket. Haiku sub-agents do the mechanical audits (Self-check over the diff, caller
lookups, scope/size), and opus is consulted at four fixed points: an uncertain gate, writing the plan, after the 2nd failed fix
attempt, and the review sign-off (opus above 200 changed lines or on plan-approved tickets, sonnet otherwise). Every skill declares
its `model:` in its frontmatter. Details: `CONVENTIONS.md` § Models and effort.

## Guardrails — hard rules in code, not only in prompts

- **Hook** `hooks/hooks.json` → `bin/harness-guard` (PreToolUse). For calls from `harness:*` agents or under `<repo>/.user/worktrees/`
  it refuses force-push, `gh pr merge|ready`, `gh pr review --approve`, `glab mr merge|approve|update --ready`, non-draft `gh pr create` /
  `glab mr create`, `git commit --no-verify`, edits to lockfiles/`go.mod` and writes to `.user/worktrees/_main`, with a reason naming the rule
  and its brief. Your own interactive work elsewhere is untouched. `bin/harness-credential-guard` (same scope) denies reads of `~/.ssh` and
  `~/.aws` credentials; `/harness:init` offers an always-on variant for the project.
- **Agents** `agents/{triager,implementer,verifier}.md`: `/harness:work` spawns `harness:<role>`; triager and verifier have no
  Edit/Write/NotebookEdit.
- **Deny list** in `templates/settings.base.json` (force-push variants, `gh pr merge|ready`, `glab mr merge|approve|update --ready`): `/harness:init` merges it into
  `.claude/settings.json`, `/harness:doctor` flags missing entries. It applies to interactive sessions too: agents open drafts and
  never merge or mark ready, and in this setup neither does Claude for you. Run those yourself.

Details: `CONVENTIONS.md` § Hard rules are enforced in code.

## Platforms

Pick the tracker (where tickets live) and the forge (where PRs/MRs live) independently in `.claude/harness.md` § Tracker:

| `tracker:` | `forge:` | Adapter | Notes |
|---|---|---|---|
| `github` | `github` | `adapters/github.md` | `gh` CLI; issues + PRs |
| `gitlab` | `gitlab` | `adapters/gitlab.md` | `glab` CLI; issues + MRs (`iid`), draft = `Draft:` title |
| `linear` | `github` or `gitlab` | `adapters/linear.md` + the forge's | Linear MCP server for skills; `LINEAR_API_KEY` for `harness-candidates` (`/harness:work`) |

Any other platform: copy `adapters/_template.md` (to the plugin for all projects, or to `<repo>/.claude/harness/adapters/` for one), set `tracker:` / `forge:`,
and add a backend class to `harness-candidates` and a branch in the forge switches (`harness-sync`, `harness-worktree`, `harness-check-pr`, `harness-inline-note`).

## Packs

`packs/laravel`, `packs/go`: `harness.md` defaults, `settings.json` allow-list, rules (laravel), githooks (laravel). See each README.

## Evals

`tests/run.sh` covers `bin/`; `plugins/harness/evals/` covers how agents behave under the briefs. Six
`claude plugin eval` cases: `triager-eligibility` (ELIGIBLE vs. needs-info), `verifier-false-finding`
(rejects a planted false finding), `implementer-draft-only` (stops at a draft PR, never merges or closes),
`work-spawn-params` (the spawn model and effort per role), `implementer-plan-consult` (plans a plan-first ticket through the opus plan consult, ships no code), `review-planted-bug`
(flags a planted bug). Each case's scaffold builds a throwaway git repo with a bare `origin` and puts a fake `gh` first on PATH
that answers from fixture JSON and logs every call, so runs stay offline; graders read that log, the git ref logs and the reply.

Run by hand after editing `briefs/` or `skills/` — every run is a full Claude session, so always cap the cost:

```bash
claude plugin eval plugins/harness --scaffold --ablation none --allow-tools Bash Write Edit --max-cost-usd 5
claude plugin eval plugins/harness --case 'triager-*' --scaffold --ablation none --allow-tools Bash --max-cost-usd 2
plugins/harness/bin/harness-eval-diff    # per case: prev → new, DROP on a fall, n/a for a new case
```

- `--scaffold` runs the cases' `scaffold.sh` (fake `gh`, fixture repo). `--ablation none`: the scaffold puts the plugin's `bin/` on
  PATH for both arms, so a no-plugin baseline arm would still run the plugin's helpers and briefs and show nothing.
  `--allow-tools Bash` (plus `Write Edit` for the `implementer-*` cases) grants the gated tools the cases use.
- Scores below 1.0 are normal (non-deterministic runs; the CLI exits 1 below `--threshold`, default 1.0). Compare runs with
  `harness-eval-diff` (reads the two newest `aggregate-result.json` under `plugins/harness/evals/results/`, which is gitignored;
  needs jq) rather than reading one run as pass/fail.
- A brief/skill behaviour change updates or adds an eval case.

## Layout

```
plugins/harness/{.claude-plugin,skills,agents,hooks,briefs,adapters,bin,evals,packs,templates,tests,CONVENTIONS.md}
```

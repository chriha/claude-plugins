---
name: init
description: Set up the harness in the current repo — detect stack, forge and tracker, write .claude/harness.md, copy the stack pack once, merge permissions, and offer to remove stale per-project copies of the pipeline
argument-hint: "[--stack laravel|go|none] [--tracker github|gitlab|linear]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Grep, Glob, AskUserQuestion, Bash(ls:*), Bash(cat:*), Bash(cp:*), Bash(mkdir:*), Bash(chmod:*), Bash(diff:*), Bash(jq:*), Bash(git remote:*), Bash(git rev-parse:*), Bash(git status:*), Bash(git check-ignore:*), Bash(harness-*:*)
---

Make this repo work with the `harness` plugin. Idempotent: re-running only fills gaps and never overwrites a file the project
already owns without asking. Plugin root (read-only source): `${CLAUDE_PLUGIN_ROOT}`.

1. **Detect** (read, don't ask when obvious):
   - Stack: `composer.json` with `laravel/framework` → `laravel`; `go.mod` → `go`; else `none` (a `--stack` argument wins).
     Package manager, scripts (`composer.json` scripts, `Makefile`, `package.json` scripts, `justfile`) → candidate commands.
   - Forge: `git remote get-url origin` host (github.com → `github`; gitlab.com or a host containing `gitlab` → `gitlab`; anything else →
     ask `github` or `gitlab`). Tracker: default = the forge's issues; a `--tracker` argument wins; a Linear MCP server in the session or
     `.mcp.json` → ask forge issues vs. Linear. `adapters/github.md`, `adapters/gitlab.md` (tracker + forge, `glab`) and
     `adapters/linear.md` (tracker only; forge from the remote) ship. Check the CLI is installed and authenticated (`gh auth status` /
     `glab auth status`) and say so when not. Linear also needs `linear_mcp:`, `linear_team:` (ask; `list_teams` offers the keys) and, for
     `/harness:work`, `LINEAR_API_KEY` in the environment. For any other platform say so, offer to copy `adapters/_template.md` to
     `.claude/harness/adapters/<name>.md` and fill it in with me, and continue with the rest.
   - Existing setup: `CLAUDE.md`, `AGENTS.md`, `.claude/commands|rules|skills|work-tickets|review-criteria.md`, `.githooks`, `.mcp.json`,
     `boost.json` / `.ai/guidelines` (Laravel Boost generates `CLAUDE.md` — never hand-edit it; project text goes into `.ai/guidelines/`).
2. **Ask once** (one `AskUserQuestion` call, only for what detection left open): stack, tracker, which commands to use for
   test / static / format / build when several candidates exist.
3. **Write `.claude/harness.md`** from `${CLAUDE_PLUGIN_ROOT}/templates/harness.md`, merging `${CLAUDE_PLUGIN_ROOT}/packs/<stack>/harness.md`
   section by section (pack content fills empty sections; commands adjusted to the detected scripts). Exists → show a diff of what would
   change and ask.
4. **Stack pack, copied once:** for `packs/<stack>/rules/*.md` → `.claude/rules/` and `packs/<stack>/githooks/*` → `.githooks/`
   (`chmod +x`; tell me to run `git config core.hooksPath .githooks` / the pack's `setup-hooks.sh`), **only files that don't exist**. Existing
   file that differs → list it, don't touch. These copies are now project-owned; `/harness:doctor` shows drift.
5. **Permissions:** merge `templates/settings.base.json` + `packs/<stack>/settings.json` + the adapter's allow-list fragment into
   `.claude/settings.json` (create if missing; union the `allow` arrays and the `deny` arrays the same way — never drop a template
   `deny` entry, and if a project `allow` entry is also in `deny`, `deny` wins: tell me; drop entries that are not valid
   `Tool(pattern)` syntax and tell me which). The `deny` list is the backstop for "agents never force-push, merge or mark ready"
   and also applies to interactive sessions. Show the resulting diff before writing.
6. **Repo hygiene:** `.gitignore` gets `.user/` when `git check-ignore .user` says it isn't ignored. No `CLAUDE.md` → write one from
   `templates/CLAUDE.md` filled with what you detected (non-Laravel only; Laravel → put it in `.ai/guidelines/` and say so). Existing
   `CLAUDE.md` > ~250 lines → suggest splitting stack rules into `.claude/rules/` (list candidates, don't do it).
7. **Stale copies:** if `.claude/commands/{work-tickets,ticket,local-code-review,work-on-comments,plan-tickets,answer-tickets,report-ticket,harness-retro,verify,architecture-loop,triage-mrs}.md`,
   `.claude/work-tickets/`, `.claude/review-criteria.md`, `.review/RULES.md`, or `scripts/work-tickets/` (also `scripts/ai/{red-check,worktree-setup,mr-inline-note}.sh`) exist, they are old per-project copies of this pipeline. For each: say
   whether the project customised it (`diff` against the plugin equivalent, summarised in a line) and offer **remove** (git history keeps
   it) / **move to `.claude/harness/<path>` as an override** (brief-shaped files only) / **keep**. Never delete without the answer.
   Then offer the always-on credential guard: a `PreToolUse` hook (`Bash|Monitor|Read|Grep|Glob`) running `harness-credential-guard --always` in the
   project's `.claude/settings.json` (the plugin's own hook only covers harness agents and worktrees); add it only when I say yes.
8. **Pipeline labels:** `create-label` (idempotent; skip ones that exist — `gh label list` / the adapter) for `planning`, `needs-info`,
   `triage`, `agent-harness`, so the pipeline never fails on a missing label. Linear: per `adapters/linear.md`.
9. **Report:** files written, files skipped, open TODOs in harness.md (empty `test:` etc.), next step `/harness:ticket`.

---
name: doctor
description: Check this repo's harness setup — missing config, overrides that drifted from the plugin, copied pack rules that differ from upstream, invalid permission entries, stale per-project pipeline copies
disable-model-invocation: true
model: sonnet
allowed-tools: Read, Grep, Glob, AskUserQuestion, Edit, Bash(ls:*), Bash(diff:*), Bash(jq:*), Bash(git log:*), Bash(git status:*), Bash(harness-*:*)
---

Read-only report first, fixes only after I pick them. Plugin root: `${CLAUDE_PLUGIN_ROOT}`.

1. **Config:** `.claude/harness.md` exists; required keys non-empty (`test:`, `test_file_glob:`, `red_check_test_cmd:`); `tracker:`/`forge:`
   adapters resolve (`harness-resolve adapters/<name>.md`); `.user/` ignored; each command in § Commands actually exists (check the binary / script).
2. **Overrides:** every file under `.claude/harness/` — diff against the plugin file of the same path. Report: *identical* (delete it),
   *differs* (summarise the delta in one line; flag when the plugin default changed after the override was made: compare `git log -1` dates),
   *orphan* (no plugin counterpart — fine for custom adapters/domains).
3. **Pack drift:** for each `.claude/rules/*.md` and `.githooks/*` that exists in `packs/<stack>/`, diff against upstream. List
   `upstream has newer lines` vs `project-specific edits`; offer to apply upstream hunks I choose.
4. **Permissions:** `.claude/settings.json` + `settings.local.json`: entries that are not valid `Tool(pattern)` syntax (e.g. `Bash(git push and git merge:*)`),
   duplicates, over-broad writers (`Bash(git push:*)` in project settings → flag), and every `deny` entry of
   `templates/settings.base.json` missing from the project's `deny` (→ *missing deny*; fix = add it, as `/harness:init` step 5 does).
   Also flag permission patterns that can never match (CONVENTIONS.md § Permission rules): `:*` after a mid-pattern `*` (`Bash(git -C * push:*)` blocks
   nothing — write `Bash(git -C * push*)`), a `deny` on a script path (blocks only that exact way of calling it), and a scoped `allow` that a broader
   `deny` overrides (deny always wins).
5. **Stale copies:** old per-project pipeline commands/briefs/scripts as in `/harness:init` step 7.
6. **Forge/tracker CLIs:** the CLI of `forge:`/`tracker:` (`gh` / `glab`) is installed and authenticated; `tracker: linear` → `LINEAR_API_KEY` is set (needed by
   `harness-candidates`) and the Linear MCP server named by `linear_mcp:` is configured; the deny list covers the forge's merge/ready/approve commands.
7. Print a table `check | status | action`, then ask which fixes to apply.

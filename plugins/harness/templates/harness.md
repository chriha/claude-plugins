# Harness config

Read by the `/harness:*` skills and briefs (see the plugin's CONVENTIONS.md). Owned by this project — edit freely.
To change a whole brief/adapter instead, copy it to `.claude/harness/<same path>` (it replaces the plugin file).

## Tracker
tracker: github    <!-- github | gitlab | linear -->
forge: github      <!-- github | gitlab (where the PRs/MRs live; Linear is a tracker only) -->
<!-- labels/priority scheme differing from the adapter's defaults go here -->
<!-- tracker: linear → also linear_mcp: (MCP server name, default linear), linear_team: (team key), linear_accept_state: (default Todo);
     /harness:work reads Linear through its API: export LINEAR_API_KEY -->

## Commands
test: 
static: 
format: 
build: 
setup-worktree: 
test-affected: 

## Scripts
test_file_glob: 
red_check_test_cmd: 
exclude_from_size: 

## Branch & commits
branch types: fix|feature|refactor|chore
commit types: feat|fix|docs|style|refactor|perf|test|chore|ci
max subject length: 72
ticket id in commit subject: no
Co-Authored-By: Claude <noreply@anthropic.com>

## Plan-first triggers
<!-- project-specific "this needs a plan first" cases, one per line -->

## Self-check
<!-- project-specific "no X" checks before each commit -->

## Test conventions
<!-- what a good test looks like here -->

## Review triggers
<!-- project-specific "a human must review this PR" cases for /harness:triage-prs, one per line (paths in CODEOWNERS count already) -->

## Never
- Change dependencies without approval.

## Models
implementer_model: sonnet    <!-- sonnet (default) | opus: run the whole implementer session on opus -->

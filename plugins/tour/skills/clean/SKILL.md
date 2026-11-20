---
name: clean
description: Prune old local tour data (worktrees, tours, chats), after confirming what goes. Starts only when the user runs it.
argument-hint: "[--older-than 30d]"
disable-model-invocation: true
model: haiku
---
# /tour:clean

Remove tour data the user no longer needs from the data dir (`${CLAUDE_PLUGIN_DATA:-~/.claude/tour}`, the one `tour-fetch`
writes). A tour is one MR/PR head: its worktree, `tour.json`, `state.json`, drafts and chats. Never delete anything yourself;
`tour-clean` does it, and only after the user confirms.

`$ARGUMENTS`: optional `--older-than <N>d|<N>w`. Default: **30d** (a tour counts as old when none of its `meta.json`,
`tour.json` and `state.json` was touched in that time; `state.json` changes when you mark progress, annotate or draft, so a tour
you keep working in stays, one you only read does not). Pass the value through to `tour-clean` unchanged (`4w` stays `4w`). Anything else: say
`usage: /tour:clean [--older-than 30d]` and stop.

1. Dry run: `${CLAUDE_PLUGIN_ROOT}/bin/tour-clean [--older-than <value>]`. It deletes nothing; it prints one `<age> <size> <dir>` line per
   tour that would go, then a `total` line. A tool error is shown as is; stop.
2. No tours listed: say so and stop.
3. Show the list and the total to the user (age, size, directory), then ask once with `AskUserQuestion`: delete these N tours
   (`Delete` or `Keep everything`).
4. `Delete`: run the same command with `--yes` appended and show its `total` line. Anything else: delete nothing and say so.

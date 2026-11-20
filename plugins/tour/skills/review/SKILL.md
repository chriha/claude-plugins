---
name: review
description: Guided tour of an MR/PR. Groups the change into chapters, explains each with evidence and opens a local web UI. Starts only when the user runs it.
argument-hint: "<id|url> [--regenerate] [--no-open]"
disable-model-invocation: true
model: opus
---
# /tour:review

Turn one GitLab MR or GitHub PR into a valid `tour.json` (contract: `${CLAUDE_PLUGIN_ROOT}/references/tour-schema.md`) and open it in
the local UI. The goal is that the reviewer **understands** the change; this is not a bug hunt. Never post comments, never run on
a trigger: the user started you. Follow `${CLAUDE_PLUGIN_ROOT}/references/writing-guide.md` for grouping, ordering and wording.

`$ARGUMENTS`: an MR/PR id or URL, plus optional `--regenerate` (ignore a cached tour) and `--no-open` (do not open the browser).
No id/URL: say `usage: /tour:review <id|url> [--regenerate] [--no-open]` and stop. Run commands from the user's clone of the project.

## 1. Fetch

1. Run `${CLAUDE_PLUGIN_ROOT}/bin/tour-fetch <id|url> [--no-open]`. It prints the meta (`dir`, `worktree`, `atoms_file`,
   `atom_count`, `title`, `description`, `ticket`, `base_sha`, `head_sha`, `cached`, `previous`). A failure (no `gh`/`glab`, bad id) is
   shown to the user as is; stop.
2. `--regenerate` set and `cached: true`: delete `<dir>/tour.json` and `<dir>/state.json` (nothing else) and run tour-fetch
   again, so it fetches fresh.
3. `cached: true` (and no `--regenerate`): **do not generate.** Go straight to step 7 (zero tokens) and say it is the cached tour
   for head `<head_sha short>`.
4. `cached: false`, `previous` not null and no `--regenerate`: this MR/PR was toured before at another head (a push since).
   Ask once with `AskUserQuestion`: **New tour** (a full tour of the current head) or **Delta tour since `<previous.head_sha short>`**
   (only what changed since that head). New tour: continue with step 2 as usual. Delta tour: run
   `${CLAUDE_PLUGIN_ROOT}/bin/tour-delta <previous.dir> <dir>` (prints and writes `<dir>/delta.json`: `unchanged` atoms paired with
   their old ids, `changed` atoms marked `new` or `changed`) and generate a delta tour (step 4, "Delta tour"). `changed` is empty:
   say the diff is the same as the previous tour's (only line positions moved), serve the previous tour
   (`tour-serve <previous.dir> --worktree <previous.dir>/worktree`, step 7), tell the user it belongs to the older head
   `<previous.head_sha short>` (annotations and posts go there; a post fails once the head moved) and stop. `previous` null: nothing to ask.

## 2. Size and estimate

Read `<dir>/atoms.json` and `<dir>/diff.patch` (delta tour: only the atoms listed in `changed`; `unchanged` atoms are not read and
not counted). Changed lines = lines starting with `+` or `-` in `atoms[].lines`. Diff tokens
= `diff.patch` bytes / 4.

| Layer | Default | Extra tokens (factor x diff tokens) |
|---|---|---|
| Base: chapters, order, what/why/impact | always on | 1.5 |
| Deep context: callers/dependents per changed symbol | off | 1.0 |
| Active review: teaser and 2-3 break-it probes per chapter | off | 0.8 |
| Architecture delta: before/after Mermaid graph | off | 0.3 |
| Rules check: flags against `CLAUDE.md` and `.claude/rules/*` | off | 0.4 |

Drift flags (`tour-drift`) are deterministic, free and always included. Chat is not part of generation. The numbers are a
heuristic: show each as `small` (< 20k tokens), `medium` (< 80k) or `large`, plus the number (`~35k`). Show the diff stats too
(files, atoms, changed lines).

Changed lines > 10000 (hard cap): say the MR is too big for one coherent tour, suggest splitting it, and stop unless the user
insists. Changed lines > 2000: say that generation runs in batches (step 4).

## 3. Cost gate

Ask once with `AskUserQuestion` (`multiSelect`): which optional layers to add, options Deep context, Active review,
Architecture delta, Rules check, each with its estimate; picking none is valid. Base is not an option. **Nothing optional is
generated, read or looked up before this answer.** The answer fixes `layers` (`base`, always `drift`, plus the chosen).
Skipped layers produce none of their fields: no `graph`, no `intent`/`probes`, no `callers`, no `rules_flags`, and no
exploration for them (no CodeGraph/grep for callers, no reading rules files).

## 4. Generate `tour.json`

Write it to `<dir>/tour.json`. Inputs: meta (ticket text, description), `atoms.json`, `diff.patch`, `worktree/` for reading the
code at the head, and `tour-drift <dir>` output for `drift`.

- `mr` and `summary` per the schema (`mr.base_sha`/`head_sha` from meta). `summary.risk_reasons` cite concrete things.
- Chapters: coherent concerns, not files and not line diffs; every atom exactly once across blocks and `mechanical`
  (`writing-guide.md`). Order: contracts/schema, domain, wiring (routes, DI, config), callers, tests, mechanical. Deviating is
  allowed with a one-line `order_reason`.
- Evidence: `why` cites the ticket text, the MR text or code, and `why_source` says which; never invent intent, write what is
  unclear and use `unclear`. `impact` names concrete symbols and files.
- `deep` chosen: for each changed symbol add `callers` (CodeGraph when `<worktree>/.codegraph/` exists, else grep in the worktree).
- `active` chosen: per chapter (not `mechanical`) `intent` and 2-3 `probes` (a question plus a test snippet in the repo's test framework). The UI shows `intent` before the reviewer predicts what changes and reveals the chapter afterwards, so it must not name the files or symbols that change.
- `arch` chosen: `graph.mermaid`, before/after of the modules the change touches.
- `rules` chosen (the UI shows each flag on its block): read the repo's `CLAUDE.md` and `.claude/rules/*` (in the worktree), add `rules_flags` to blocks that break a
  rule, quoting the rule and its source file; no flag when nothing is broken.
- **Delta tour** (chosen in step 1): chapters cover only the `changed` atoms of `<dir>/delta.json`; read and explain nothing else.
  Put every `unchanged` atom in `mechanical.atoms` with `mechanical.note`
  `Unchanged since <previous.head_sha short>: see the earlier tour (<previous.dir>/tour.json)`. When the previous tour is itself a delta
  tour, an atom paired with one of its `mechanical` atoms points on to the tour that note names (join the references with `; `), so
  the reference always leads to the tour that explains it. They are not re-explained, read or
  looked up, so they cost no tokens. A `changed` atom of a file the old head touched (`status: changed`) is a new version of
  something the earlier tour explained: say what is different now, not the whole story again. `delta.json` `removed` lists old atoms the push dropped or reworked: name them in `summary.approach`
  (the earlier tour still describes them). Set `summary.intent` and `approach` for
  the push (what it changes), and add to `summary.risk_reasons` only reasons that come from the delta. Layers, drift and
  validation work as in a full tour; `tour-drift` still runs over the whole MR.
- **Big MR (changed lines > 2000):** group atoms by top-level directory (split a huge directory by subdirectory), generate the
  chapters of each batch separately with only that batch's atoms, then merge: join chapters that belong together, re-apply
  the reading order across batches, write `summary` once from all of them, and re-check coverage.

## 5. Validate and repair

Run `${CLAUDE_PLUGIN_ROOT}/bin/tour-validate <dir>/tour.json <dir>/atoms.json`. Exit 0: continue. Exit 1: it lists
`<json path>: <reason>` per line; repair exactly those paths (a dropped atom goes into the chapter block where it belongs, or
into `mechanical`; never delete other content), then run it again. At most **2 repair rounds**. Still invalid after the
second: keep the file, tell the user it is invalid and which errors remain, do not serve it, stop. Exit 2: a usage or JSON
problem; fix the file's syntax the same way, counts as a round.

## 6. Report

One short paragraph: chapter count, layers included, risk and any `unclear` blocks the reviewer should look at first.

## 7. Open

Unless `--no-open`: `${CLAUDE_PLUGIN_ROOT}/bin/tour-serve <dir> --worktree <dir>/worktree` (run it in the background; it prints
the URL with its token, show that URL). With `--no-open`: do not start it; print the exact command (`tour-serve <dir> --worktree <dir>/worktree`) for the user to run. The server runs until stopped; tell the user how to stop it.

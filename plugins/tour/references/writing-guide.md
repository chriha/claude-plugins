# Writing guide for /tour:review

How to turn atoms into a tour a reviewer can follow. The shape is fixed by `tour-schema.md`; this file is how to fill it.
Goal: after the tour the reviewer can explain the change to someone else. Not a bug hunt, no verdicts.

## Group: chapters are concerns

- One chapter = one thing the change does ("Reject empty imports", "Return an ImportResult"), 2-6 blocks. Not a file, not a
  directory, not a hunk.
- A block = atoms that tell one step together (a rule and its constant, a function and its only call site). One atom can be a block.
- A file that serves two concerns is split by atom. Two files that serve one concern share a chapter.
- Every atom goes exactly once to a block or to `mechanical` (lockfiles, formatting, renames, generated files). Check the count
  before you finish; `tour-validate` will catch a miss, but each repair round costs.
- Title chapters with the outcome, not the file names. Aim for 3-8 chapters; more than 10 means the groups are too fine.

## Order: how you would explain it

contracts/schema (types, API shape, migrations) -> domain logic -> wiring (routes, DI, config) -> callers -> tests -> mechanical.
Deviate when the story reads better (a refactor whose tests come first), and then say so in `order_reason`, one line,
"Domain next: the rules the contract promises" style. Never leave `order_reason` generic ("logical order").

## Explain: what, why, impact

- `what`: the behaviour change in one or two sentences, present tense, no line-by-line narration.
- `why`: cite the source. Ticket text ("SHOP-1370 asks for empty payloads to be rejected"), MR text, or the code itself
  ("the caller on line 40 already assumes a non-empty list"). Set `why_source` to `ticket`, `mr` or `code` accordingly.
- Nothing supports a reason: write `Not stated in the ticket or the MR text.` and `why_source: "unclear"`. Never invent intent;
  an honest `unclear` is better than a plausible guess. Do not reuse `what` as `why`.
- `impact`: concrete symbols and files affected ("`ImportService::run` now returns `ImportResult`; `ImportController` reads it"),
  never "may affect other parts". Empty is fine for a change with no reach.
- `watch`: things a reviewer should check by hand (an N+1 query, a status code that changed for clients). Empty when nothing.
- `summary.risk` follows the reasons you can name: `low` none, `medium` a behaviour or contract change, `high` data loss, auth,
  money or an irreversible format. `risk_reasons` states each concretely.

## Optional layers (only when the cost gate chose them)

- `deep`: `callers` = who calls or depends on the changed symbol, as `{symbol, file}`; real hits only, from CodeGraph or grep.
- `active`: `intent` is a one-line teaser that does not give the answer away; `probes` are 2-3 "how could this break" questions,
  each with a short test snippet in the repo's framework (look at an existing test for the style).
- `arch`: a small Mermaid `graph` of the touched modules before and after; no more than ~12 nodes.
- `rules`: flag only a clear break of a written rule; quote the rule, name its file; skip style opinions.
- Layer not chosen: write none of its fields and do none of its research.

## Big changes

Above ~2000 changed lines: batch atoms by directory, write each batch's chapters alone, then merge (join chapters of one
concern across batches, re-apply the order, write `summary` once). Above 10000: suggest splitting the MR instead.

## Before you validate

- Atom coverage: every id once. `layers` matches the fields present. Ids unique. No empty strings.
- Each `why` has a source; each `impact` names a symbol; each chapter has an `order_reason`.

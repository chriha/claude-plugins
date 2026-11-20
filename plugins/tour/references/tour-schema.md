# tour.json schema (version 1)

The contract between the generating skill (`/tour:review`), the validator (`bin/tour-validate`) and the UI. This file is the
single source of truth: change it first, then the validator, fixtures and UI.

Validate with `bin/tour-validate <tour.json> <atoms.json>`. It prints nothing and exits 0 when valid. Otherwise it prints one
`<json path>: <reason>` per line on stderr and exits 1 (exit 2: unreadable or not JSON). Fix loop in the skill: run it, repair
exactly the listed paths, run again, at most 2 repair rounds.

Fixtures to build the UI against, both valid for `fixtures/atoms.json`:
- `fixtures/tour.full.json`: all six layers, GitLab.
- `fixtures/tour.base.json`: base layer only, GitHub, no `ticket`.

## atoms.json (input, written by `tour-fetch`)

```json
{"version": 1, "atoms": [
  {"id": "a1", "file": "app/Http/Requests/ImportRequest.php",
   "old": {"start": 18, "count": 1}, "new": {"start": 18, "count": 4},
   "lines": ["-            'rows' => ['array'],", "+            'rows' => ['required', 'array', 'min:1'],"]}
]}
```

An atom is one `git diff -U0` hunk. The validator only needs `atoms[].id` (unique, non-empty string); a bare array of atoms is
accepted too. `file`, `old`, `new` and `lines` are for the UI.

## Top level

| Field | Type | Required | Rule |
|---|---|---|---|
| `version` | integer | yes | `1` |
| `mr` | object | yes | see below |
| `layers` | string[] | yes | subset of `base`, `deep`, `active`, `arch`, `rules`, `drift`; must include `base`; no duplicates |
| `summary` | object | yes | see below |
| `drift` | object[] | iff layer `drift` | may be empty. Not allowed without the layer |
| `graph` | object | iff layer `arch` | `{"mermaid": "<source>"}`. Not allowed without the layer |
| `chapters` | object[] | yes | non-empty; chapter ids unique; in reading order |
| `mechanical` | object | yes | see below |

Unknown extra fields are ignored by the validator and must be ignored by the UI.

## `mr`

| Field | Type | Required | Rule |
|---|---|---|---|
| `platform` | string | yes | `gitlab` or `github` |
| `project` | string | yes | `group/project` or `owner/repo` |
| `iid` | integer | yes | MR iid / PR number, >= 1 |
| `title`, `url` | string | yes | non-empty |
| `base_sha`, `head_sha` | string | yes | non-empty (the diff is against the merge base; `head_sha` keys the cache) |
| `ticket` | object | no | `{"id": "<non-empty>", "summary": "<non-empty>"}`; omit when no ticket is linked |

## `summary`

| Field | Type | Required | Rule |
|---|---|---|---|
| `intent` | string | yes | what the change is for, from ticket/MR text |
| `approach` | string | yes | how it does it |
| `risk` | string | yes | `low`, `medium` or `high` |
| `risk_reasons` | string[] | yes | may be empty; each non-empty |

## `drift[]` (layer `drift`)

Deterministic flags from `tour-drift`.

| Field | Type | Required | Rule |
|---|---|---|---|
| `kind` | string | yes | free text, e.g. `new_dependency`, `new_migration`, `new_config_key`, `changed_route`, `new_top_level_dir` |
| `detail` | string | yes | what exactly |
| `atoms` | string[] | yes | atom ids; each must exist in `atoms.json`. A reference, not an assignment: it does not count for coverage |

## Chapter (`chapters[]`)

| Field | Type | Required | Rule |
|---|---|---|---|
| `id` | string | yes | unique across chapters |
| `title` | string | yes | |
| `order_reason` | string | yes | one line: why here (contracts, domain, wiring, callers, tests) |
| `blocks` | object[] | yes | non-empty |
| `intent` | string | iff layer `active` | the teaser shown before the reveal. Not allowed without the layer |
| `probes` | object[] | iff layer `active` | may be empty. Not allowed without the layer |

### Block (`chapters[].blocks[]`)

| Field | Type | Required | Rule |
|---|---|---|---|
| `atoms` | string[] | yes | non-empty; atom ids that exist in `atoms.json` |
| `what` | string | yes | what the change does |
| `why` | string | yes | why, citing the ticket, the MR text or code; write what is unclear when it is |
| `why_source` | string | yes | `ticket`, `mr`, `code` or `unclear`. `unclear` is a valid answer; the UI flags it to the reviewer |
| `impact` | object[] | yes | may be empty; see below |
| `watch` | string[] | yes | things to check; may be empty |
| `rules_flags` | object[] | no | only with layer `rules`; each `{"rule", "source", "note"}`, all non-empty strings |

`impact[]`: `{"symbol", "file", "note"}`, all non-empty strings. With layer `deep` an entry may also carry
`callers`: `[{"symbol", "file"}]` (callers/dependents of that symbol). `callers` is not allowed without the layer.

### Probe (`chapters[].probes[]`)

`{"question": "<non-empty>", "snippet": "<non-empty test snippet in the repo's framework>"}`.

## `mechanical`

`{"atoms": [<atom ids>], "note": "<non-empty>"}`. Lockfiles, formatting, renames and generated files. They stay listed (the UI
collapses the chapter) but need no explanation. `atoms` may be empty.

## Coverage (enforced)

Every atom in `atoms.json` must appear **exactly once** across all `chapters[].blocks[].atoms` and `mechanical.atoms`:
- unassigned: `$: atom "a7" is not assigned to any block or to mechanical`
- assigned twice: `$.chapters[1].blocks[0].atoms[1]: atom "a1" is assigned twice (first at $.chapters[0].blocks[0].atoms[0])`
- not in `atoms.json`: `$.chapters[0].blocks[0].atoms[1]: unknown atom id "zz" (not in atoms.json)`

## Layer rules

A field that belongs to an optional layer is valid only when that layer is in `layers`, and is required when it is (as marked
above). Layer to fields: `drift` -> `drift`; `arch` -> `graph`; `active` -> `chapters[].intent`, `chapters[].probes`; `deep` ->
`impact[].callers`; `rules` -> `blocks[].rules_flags`. Violations read
`$.chapters[0].intent: only valid when layer "active" is listed in layers`.

## Example (base layer)

```json
{
  "version": 1,
  "mr": {"platform": "github", "project": "acme/shop-api", "iid": 88, "title": "Reject empty import payloads",
         "url": "https://github.com/acme/shop-api/pull/88", "base_sha": "1f0c2d9", "head_sha": "8a9b0c1"},
  "layers": ["base"],
  "summary": {"intent": "Reject empty imports.", "approach": "Validate in ImportRequest.", "risk": "low", "risk_reasons": []},
  "chapters": [{
    "id": "c1", "title": "Validation", "order_reason": "Contract first.",
    "blocks": [{
      "atoms": ["a1"],
      "what": "ImportRequest requires a non-empty rows array.",
      "why": "The PR description asks for empty payloads to be rejected.", "why_source": "mr",
      "impact": [{"symbol": "ImportRequest::rules", "file": "app/Http/Requests/ImportRequest.php", "note": "Empty rows now return 422."}],
      "watch": []
    }]
  }],
  "mechanical": {"atoms": ["a2"], "note": "composer.lock"}
}
```

A complete example with every layer is `fixtures/tour.full.json`.

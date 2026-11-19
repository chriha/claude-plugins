# Adapter: GitLab (issues + merge requests, `glab` CLI)

Tracker **and** forge. `<n>` = the issue / MR **iid** (the per-project number), referenced as `#<n>` for issues and `!<n>` for MRs.
Ticket id regex: `#?(\d+)`. Worktree name: `issue-<n>`. "PR" in the briefs and skills means **merge request** here.
Closing keyword: `Closes #<n>` in the MR description (GitLab closes the issue **only** when the MR merges into the default branch; a keyword on an MR targeting another branch does not fire).
Reference form (non-final slice of a multi-MR plan, must not close the ticket): `Related to #<n>`.
Branch ↔ ticket: branch `<type>/<n>-<slug>`; the leading number after `<type>/` is the ticket.

`glab` runs against the repo's `origin`; `projects/:id/…` in `glab api` is resolved by `glab` itself. Self-managed hosts: `glab auth login --hostname <host>`
and `GITLAB_HOST` when `origin` is not the default. MR **draft** = title prefix `Draft: ` (what `glab mr create --draft` sets).

## Tracker operations

| Operation | Command |
|---|---|
| read-ticket | `glab issue view <n> --output json` (title, description, labels, state, assignees, created_at) + `glab issue view <n> --comments` (or `glab api projects/:id/issues/<n>/notes?per_page=100`) |
| list-tickets (mine, open) | `glab issue list --assignee=@me --output json --per-page 100` |
| list-triage | `glab issue list --label triage --output json --per-page 100` |
| search-tickets | `glab issue list --search "<kw>" [--all] --output json` |
| create-ticket | `glab issue create --title … --description "$(cat <f>)" --label … [--assignee <me>] --no-editor` (omit `--assignee` for triage issues); `<me>` = `glab api user --jq .username` |
| edit-description | read the description to a scratchpad file → change only your sections → `glab issue update <n> --description "$(cat <f>)"` (re-read right before writing) |
| comment | `glab issue note <n> -m "…"` |
| add-label / remove-label | `glab issue update <n> --label <l>` / `--unlabel <l>` |
| create-label (once) | `glab label create --name <name> --color "#<hex>"` |
| assign-me | `glab issue update <n> --assignee @me` |
| set-priority | `glab issue update <n> --label priority:<1-4>` and `--unlabel` any other `priority:*` |
| accept-triage | `glab issue update <n> --unlabel triage --assignee @me` |
| close-not-planned | `glab issue close <n>` (GitLab has no "not planned" reason: add the comment `Not planned: <why>` first) |
| close-duplicate | `comment` `Duplicate of #<m>` → `glab issue close <n>`; also `glab api -X POST projects/:id/issues/<n>/links -f target_project_id=<id> -f target_issue_iid=<m> -f link_type=relates_to` |
| blockers-read | `glab api projects/:id/issues/<n>/links` → entries with `link_type: "is_blocked_by"` (field `iid`, `state`) |
| blockers-add | `glab api -X POST projects/:id/issues/<n>/links -f target_project_id=<id> -f target_issue_iid=<blocker> -f link_type=is_blocked_by` (`<id>` = `glab api projects/:id --jq .id`; issue links need a tier that supports `blocks`; else write `Blocked by: #<m>` under `## Reference`) |
| related | `…/links` with `link_type=relates_to` **and** `Related: #<m>` under `## Reference` |
| in-flight | an open issue with an open MR whose source branch is `<type>/<n>-*` (`glab mr list --output json`); no label |
| collision-search | `glab mr list --output json --per-page 100` + 2–3 `search-tickets` on the `## Touches` names |
| ticket-of-pr | `Closes #<n>` / `Related to #<n>` in the MR description (`glab mr view <mr> --output json`), then in the commit log, then the branch number |
| harness-issues | `glab issue list --label agent-harness --all --search "<key>" --output json` |
| status-of-ticket | the issue's MR state: open MR → in review; merged into the default branch → done (GitLab closes it); merged into another branch (a stacked MR merged into its base) → still in review, the issue stays open until the work reaches the default branch via the base MR (`/harness:work` Step 0 retargets a stacked MR to the default branch once its base merged — merge stacked MRs in chain order so the keyword fires) |

Priority: labels `priority:1` (urgent) … `priority:4` (low); `priority::<n>` (scoped) is read too; none sorts last. Type labels: `bug`, `feature`, `improvement`.
Special labels: `on hold`, `ready-for-human` (not for agents) · `needs-info` · `planning` · `triage` · `agent-harness`.
Dedupe key for harvest issues: first line of the description `Key: <key>`.

## Forge operations

| Operation | Command |
|---|---|
| list-prs (open) | `glab mr list --output json --per-page 100` (fields `iid`, `title`, `source_branch`, `target_branch`, `web_url`, `draft`, `labels`, `sha`, `author`) |
| pr-of-branch | `glab mr list --source-branch <branch> --all --output json` |
| view-pr | `glab mr view <n> --output json` (`source_branch`, `target_branch`, `sha`, `draft`, `state`, `description`, `web_url`, `diff_refs`, `head_pipeline`) |
| pr-diff | `glab mr diff <n> --raw` |
| create-draft-pr | `glab mr create --draft --target-branch <base> --source-branch <branch> --title "<first commit subject>" --description "$(cat <f>)" --yes` (`--draft` always; `--remove-source-branch` only when the project's convention says so) |
| edit-pr-base | `glab mr update <n> --target-branch <base>` |
| pr-template | `.gitlab/merge_request_templates/*.md` (`Default.md` first) if present |
| comment-pr (general) | `glab mr note <n> -m "…"` (older glab: `glab mr note create <n> -m …`) |
| comment-pr (inline) | `harness-inline-note <n> <file> <new_line> <body\|->` — posts a diff discussion via `glab api projects/:id/merge_requests/<n>/discussions` with `diff_refs`, falls back to a general note on HTTP 400 |
| review-threads | `glab api "projects/:id/merge_requests/<n>/discussions?per_page=100" --paginate` (`notes[].resolvable`, `notes[].resolved`, `notes[].position`, `notes[].author`, `individual_note`) |
| reply-to-comment | `glab api -X POST projects/:id/merge_requests/<n>/discussions/<discussion id>/notes -f body='…'` |
| resolve-thread | `glab api -X PUT projects/:id/merge_requests/<n>/discussions/<discussion id> -f resolved=true` |
| merged / closed state | `glab mr list --source-branch <branch> --all --output json` → `.[0].state` (`merged` / `closed` / `opened`) |
| pr-mine-open | `glab mr list --author=@me --output json` |
| pr-label | `glab mr update <n> --label <l>` / `--unlabel <l>` (create the label once with `glab label create`) |
| pr-ci-status | `glab api projects/:id/merge_requests/<n>` → `.head_pipeline.status` and `.head_pipeline.sha` (compare with `.sha`; none or older sha = not run) |
| pr-notes (all) | `glab api "projects/:id/merge_requests/<n>/notes?sort=desc&per_page=100"` (system notes have `system: true`) |
| mr-versions (head at a note's time) | `glab api projects/:id/merge_requests/<n>/versions` (`head_commit_sha`, `created_at`) |
| current-user | `glab api user --jq .username` |
| codeowners | `.gitlab/CODEOWNERS`, else `CODEOWNERS`, else `docs/CODEOWNERS` |

Rules: MRs are always **draft** when agents open them; nobody runs `glab mr merge`, `glab mr approve`, `glab mr update --ready` (or removes
`Draft:` from the title). Pushes need the sandbox off. A pipeline that has not finished is not a reason to wait — report its status.

## Allow-list fragment (for `.claude/settings.json`)
`Bash(glab issue list:*)`, `Bash(glab issue view:*)`, `Bash(glab mr list:*)`, `Bash(glab mr view:*)`, `Bash(glab mr diff:*)`, `Bash(glab label list:*)` (read-only);
writers (`glab issue create|update|note|close`, `glab mr create|update|note`, `glab api`, `glab label create`) are granted per skill via `allowed-tools`.

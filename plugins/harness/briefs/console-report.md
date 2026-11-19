# Console report layout (every skill that ends with a report)

The final console report of a skill answers "what needs me, and why" at the top. `work`, `review`, `triage-prs` and
`work-on-comments` print this layout (`work-on-comments` also in its autonomous default run: replies posted, threads resolved and fixes pushed go under `DONE`; unfixed comments, failed gates and failed pushes under `NEEDS YOU`); only the `── details ──` block is the skill's own. It is the console output, not the
`.user/reports` file.

**Status words (shared):** `done | partial | blocked | failed | skipped | needs-info | planned | aborted`. A skill may add its own
nouns for its items (`filed`, `answered`, `approved`, a triage lane). Read-only reports have no PR state and no header sha; their scope
is the window, range or target.

**Layout, in this order. Omit empty sections.**

1. **Header:** `━━ /harness:<skill> · <scope> ━━` (scope: base sha, PR or ticket id).
2. **`VERDICT`:** counts per bucket, e.g. `2 ready · 3 need you · 1 no PR`; the skill may use its own nouns.
3. **`NEEDS YOU`:** every item that needs a human action: partial, blocked, failed, needs-info, planned, aborted, skipped gates and
   steps, open threads, push failures. Per item:
   - line 1: `<id> · <status> · <PR state>`
   - line 2 (indented): the reason
   - line 3 (indented): `→ <exact next command or action>`
4. **`READY FOR REVIEW`** (or `DONE`): one line each: `<id> · <status> · <PR state>`. PR state is one of `draft`, `✓verified`,
   `docs-only`, `none`, followed by the PR/MR reference.
5. **`NO ACTION`:** one line each, with the reason (skipped by triage, already merged, nothing to do).
6. **`Also:`** one line for side effects: new triage tickets, cleaned worktrees, harvest candidates.
7. **`── details ──`:** everything else (tables, evidence), in the skill's own shape.

Every outcome the skill can produce maps to exactly one of sections 3 to 5. An item that is both finished and has a skipped step goes
under `NEEDS YOU` (the skip is the action), not under `READY FOR REVIEW`.

Example:

```
━━ /harness:work · main 1a2b3c4 ━━
VERDICT  1 ready · 2 need you · 1 no PR

NEEDS YOU
#812 · partial · draft PR #2150
    static analysis red after 3 attempts (class: checks-red)
    → fix it in .user/worktrees/issue-812, then /harness:work 812
#820 · needs-info · none
    which endpoint should return the new field?
    → /harness:ticket 820

READY FOR REVIEW
#815 · done · draft ✓verified PR #2151

NO ACTION
#830 · skipped · already has an open PR

Also: 1 triage ticket filed (#834); 2 worktrees cleaned

── details ──
<the skill's own tables and evidence>
```

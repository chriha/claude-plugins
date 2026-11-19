---
name: build
description: Execute PROJECT_PLAN.md (written by /project:setup) to set up the whole project skeleton phase by phase, verifying each phase and reporting the manual steps left for the user.
argument-hint: "[path to plan, default PROJECT_PLAN.md]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion, WebSearch, WebFetch
---

Execute the project plan at `$ARGUMENTS` (default `./PROJECT_PLAN.md`). You are starting from a fresh context: the plan is
the only source of truth. It was written to be self-contained.

1. **Read the whole plan** first. Then check its "Prerequisites" section against the machine (`command -v`, versions). Missing tools
   → tell the user exactly what to install and wait; do not improvise substitutes for decided tools.
2. **Work phase by phase, in order.** For every task: do it, run its acceptance check, and tick its checkbox in
   `PROJECT_PLAN.md` (Edit) immediately, so an interrupted run can resume exactly where it stopped. If the plan has
   unticked boxes on start, resume at the first one, after re-verifying the last ticked phase's acceptance check.
3. **Follow the decisions.** Don't swap tools, versions or structure because you'd prefer something else. If something in the
   plan is impossible or wrong (a package no longer exists, a flag changed), fix it minimally, note it in the plan's
   "Deviations" section with the reason, and continue. Ask the user only when the fix changes a recorded decision.
4. **Skeleton only.** No product features beyond the plan's single proof-of-life slice.
5. **Never do these yourself** (list them as manual steps instead): creating cloud accounts, entering secrets or API keys,
   pushing to a remote or creating the remote repo unless the plan says so and the user confirms, branch protection or
   other settings on the forge, `/plugin install ...` commands (the user runs them).
6. **Verify at the end.** Run the plan's "Final verification" commands (install from clean, lint, static analysis, tests,
   build, Docker build/up, CI config lint where possible). Everything must pass. Fix failures; don't report success over a red check.
7. **Report**: what was built (file tree), verification results with actual output summaries, deviations, and the
   remaining **manual steps** as a checklist for the user, in order. Suggest deleting `.project-setup/` and moving `PROJECT_PLAN.md` to
   `docs/` or removing it after they've reviewed it. Offer an initial commit.

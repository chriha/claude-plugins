# project: a Claude Code project setup wizard

You have an idea but not a stack. `/project:setup` interviews you, recommends the best option whenever you say
"not sure", and writes a complete `PROJECT_PLAN.md`. A fresh Claude session can execute that plan to set up the whole
project skeleton (tooling, structure, quality, CI, containers, docs, Claude config) with nothing forgotten.

## Install

Inside Claude Code:

```
/plugin marketplace add chriha/claude-plugins
/plugin install project@chriha
/reload-plugins
```

Or from the shell:

```
claude plugin marketplace add chriha/claude-plugins
claude plugin install project@chriha
```

For local development, add the marketplace from a checkout (`/plugin marketplace add /path/to/claude-plugins`),
or run `claude --plugin-dir /path/to/claude-plugins/plugins/project` for a single session.
Update later with `claude plugin marketplace update chriha`.

## Use

```
mkdir my-new-thing && cd my-new-thing && claude
/project:setup a habit tracker for small teams     # idea is optional
```

1. **Preflight**: detects an empty dir vs. existing code, resumes an interrupted interview.
2. **Interview** in six rounds: foundations → stack → data & services → quality → delivery → collaboration & Claude setup.
   Each question has a recommended option and a "Not sure, you pick" option.
   Decisions are saved to `.project-setup/decisions.md` after every round.
3. **Confirm**: decision table; you can change anything.
4. **Plan**: an Opus sub-agent (`project:plan-writer`) verifies current versions on the web and writes `PROJECT_PLAN.md`.
5. **Build**: start a fresh session and run `/project:build`. It executes the phases, ticks checkboxes, verifies,
   and lists the manual steps (accounts, secrets, forge settings, plugin installs) left for you.

## Update an existing project

```
cd my-existing-project && claude
/project:update                    # or: /project:update CI and docs
```

1. **Audit**: checks the repo against the wizard's checklist (tooling, quality, tests, CI, Docker, docs, Claude config)
   and reports what is present, partial and missing, with evidence.
2. **Choose**: you pick which gaps to close; the rest is recorded as out of scope.
3. **Interview**: only the gaps, with your existing stack and conventions as the baseline (extend, don't replace).
4. **Plan**: `plan-writer` writes an incremental `PROJECT_PLAN.md` that adds only what is missing and merges into existing files.
5. **Build**: `/project:build` executes it, same as for a new project.

## Layout

```
.claude-plugin/plugin.json
skills/setup/SKILL.md      the interview (/project:setup)
skills/update/SKILL.md     audit + gap interview for existing projects (/project:update)
skills/build/SKILL.md      the executor (/project:build)
agents/plan-writer.md      Opus plan author
references/                interview guide, audit guide, recommendation heuristics, plan template and completeness checklist
```

Tune the wizard by editing `references/`: add topics to `interview-guide.md`, change defaults in `recommendations.md`.

## Harness integration

When Claude setup comes up, the wizard offers [harness plugin](../harness) from this marketplace. If chosen,
the plan lists the install commands as manual steps and runs `/harness:init` after the skeleton exists.

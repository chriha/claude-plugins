# claude-plugins

Marketplace `chriha` with three Claude Code plugins: `harness` (ticket → plan → implement → review pipeline) and `project` (`/project:setup`, `/project:update`, `/project:build`) and `tour` (guided MR/PR review, `/tour:review`; in development). User docs: `README.md` and `plugins/<name>/README.md`. The harness contract between skills, briefs and project config is `plugins/harness/CONVENTIONS.md`.

## Commands
- Test (harness): `bash plugins/harness/tests/run.sh` (needs git, go)
- Static: `for p in plugins/*; do claude plugin validate "$p" --profile directory; done`
- Harness eval (by hand, after editing `briefs/` or `skills/`; costs money): `claude plugin eval plugins/harness --scaffold --ablation none --allow-tools Bash Write Edit --max-cost-usd 5`; narrow with `--case '<name>'`; results in `plugins/harness/evals/results/` (gitignored)
- Eval diff: `plugins/harness/bin/harness-eval-diff` (needs jq)
- Release: `scripts/release <plugin> [patch|minor|major|X.Y.Z]` (from a clean `main`; bumps that plugin's `plugin.json`, tags `<plugin>-vX.Y.Z`, pushes)
<!-- keep in sync with .claude/harness.md § Commands -->

## Layout
- `.claude-plugin/marketplace.json`: the marketplace (`chriha`); add new plugins here
- `plugins/harness/`: `skills/` (`/harness:*`), `briefs/`, `adapters/`, `packs/`, `templates/`, `bin/` (tested by `tests/run.sh`), `evals/`, `hooks/`, `agents/`
- `plugins/project/`: `skills/{setup,update,build}`, `agents/plan-writer.md` (Opus), `references/` (interview guide, recommendations, plan template and checklist; edit there to tune the wizard)
- `plugins/tour/`: `skills/{review,clean}`, `references/`, `bin/`, `server/`, `ui/`, `tests/run.sh` (scaffold only; stands alone, no dependency on harness)

## Conventions
- Edit the source here, never the installed copy under `~/.claude*/plugins/cache/`.
- Prompts and references are the product: concrete, short, consistent with each other.
- harness: skills, briefs and adapters stay consistent with CONVENTIONS.md (change the contract first); `bin/` scripts are portable bash (macOS + Linux) and every behaviour change gets a case in `tests/run.sh`; a brief/skill behaviour change updates or adds an eval case.
- project: a change to the plan template usually needs the checklist and `agents/plan-writer.md` updated too; generated plans are skeleton-only, no product features.

## Git
- Branches: `<type>/<id>-<slug>`; Conventional Commits with the plugin as scope (`fix(harness): …`, `feat(project): …`); PRs closed via the tracker's closing keyword. Agents open drafts and never merge or mark ready.

## Agent workflow
Ticket pipeline via the `harness` plugin: `/harness:ticket`, `/harness:work`, `/harness:review`, `/harness:work-on-comments`.
Project config: `.claude/harness.md`; overrides: `.claude/harness/`.

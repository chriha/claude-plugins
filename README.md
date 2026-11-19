# claude-plugins

Christopher Hartmann's Claude Code plugins, one marketplace (`chriha`).

```
/plugin marketplace add chriha/claude-plugins
/plugin install harness@chriha
/plugin install project@chriha
```

| Plugin | What it does | Docs |
|---|---|---|
| `harness` | Ticket → plan → implement → review pipeline for any repo, forge and tracker (`/harness:*`) | [plugins/harness](plugins/harness/README.md) |
| `project` | Interview-driven project setup: `/project:setup`, `/project:update`, `/project:build` | [plugins/project](plugins/project/README.md) |

Update with `/plugin marketplace update chriha`, then `claude plugin update <name>`.

## Layout

```
.claude-plugin/marketplace.json
plugins/<name>/        one directory per plugin, each with its own .claude-plugin/plugin.json
scripts/release        scripts/release <plugin> [patch|minor|major|X.Y.Z]
```

Develop locally by adding a clone as the marketplace: `/plugin marketplace add /path/to/claude-plugins`.

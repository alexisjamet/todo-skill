# todo-skill

A [Claude Code](https://code.claude.com) skill that lets you **queue tasks while Claude is working**, for one or several projects at once, without interrupting what is under way — and that **starts independent tasks in parallel** with background agents.

```
/todo fix the 404 on /pricing
/todo api: rate-limit the /export endpoint
/todo web: add the legal links to the footer; api: log failed logins
/todo web: redo the pricing table, sub-agent, sonnet, effort medium
/todo
/todo api
```

Claude answers in one line (`Noted: 1 in api, 1 in web (agent web-footer).`) and goes back to its current task. When that task is done, it picks the next pending item by itself. Every task ends in an open pull request: **nothing is merged or deployed unless you explicitly ask.**

## How it works

- **One list per project**, in `.claude/todo.md` (or another path the project's `CLAUDE.md` / `AGENTS.md` names) on a dedicated **`todo` branch** of each repository. Every session — local, cloud, parallel — sees the same queue, and updating it never touches the default branch: no merge, no deployment.
- **Several projects in one session**: every git repository Claude can work in (extra working directories, repositories attached to a cloud session) is a project. A request goes to the project you name (`api: …`, `@api …`), else to the one it obviously refers to, else to the current one. The confirmation always says where it went.
- **Parallel agents, only when safe**: a request starts right away in a background agent (its own branch and worktree, its own PR) if it touches a different part from everything in flight and needs no decision from you. Tasks in different projects are always independent. There is no fixed cap: the session picks the orchestration that suits the queue.
- **You merge**: agents open PRs and never merge, push to the default branch or deploy. The main conversation rebases and checks their branches; it merges or deploys only when you ask — in the conversation, or in a project's instructions — one PR at a time per project.

- **Who runs a task, and how hard it thinks**: add `sub-agent` to have a task done by an agent rather than the main conversation, and optionally a model (`sonnet`, `haiku`, …) and an effort (`low` to `max`). A session on Opus at high effort can queue a routine task at medium effort, or on a cheaper model. The options are kept on the task's line, `{sub-agent, model: sonnet, effort: medium}`, and passed to the agent; they never jump the queue.

Statuses:

| Mark | Meaning |
| --- | --- |
| `[ ]` | pending |
| `[>]` | in progress in the main conversation |
| `[~]` | handed to a parallel agent |
| `[?]` | blocked on a question for you |
| `[x]` | done, PR open for you, with its URL on the line (kept 7 days) |

See [`examples/todo.md`](examples/todo.md) for a list in practice and [`skills/todo/SKILL.md`](skills/todo/SKILL.md) for the full behaviour.

## Install

**As a plugin** (updates with the repository):

```
/plugin marketplace add alexisjamet/todo-skill
/plugin install todo@todo-skill
```

Plugin skills are namespaced by the plugin, so it is invoked as `/todo:todo`.

**As a plain skill**, for a bare `/todo` — for all your projects:

```bash
git clone https://github.com/alexisjamet/todo-skill /tmp/todo-skill && mkdir -p ~/.claude/skills && cp -r /tmp/todo-skill/skills/todo ~/.claude/skills/
```

or for one repository (shared with everyone who works on it, cloud sessions included):

```bash
mkdir -p .claude/skills && cp -r /tmp/todo-skill/skills/todo .claude/skills/
```

## Tailoring it to a project

The skill reads each project's instructions rather than hard-coding anything. In `CLAUDE.md` or `AGENTS.md` you can state:

- **the parts** of the project (packages, apps, services, a `docs/features/` folder…) — two tasks on the same part never run in parallel;
- **the check command** agents must get green before opening a PR;
- **what needs your approval** (dependencies, migrations, infra config…) — such tasks are never started in parallel;
- **how to deliver**: if you want the work merged or deployed without asking, say so there — otherwise PRs stay open;
- **another path** for the list, if `.claude/todo.md` does not suit you.

## License

[MIT](LICENSE)

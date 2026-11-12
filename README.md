# todo-skill

A [Claude Code](https://code.claude.com) skill that lets you **queue tasks while Claude is working**, for one or several projects at once, without interrupting what is under way — and that **starts independent tasks in parallel** with background agents.

```
/todo fix the 404 on /pricing
/todo api: rate-limit the /export endpoint
/todo web: add the legal links to the footer; api: log failed logins
/todo web: redo the pricing table, sub-agent, sonnet, effort medium
/todo
/todo api
/todo first k7q
/todo drop k7q
```

Claude answers in one line (`Noted: 1 in api, 1 in web (agent web-footer).`) and goes back to its current task. When that task is done, it picks the next pending item by itself. Every task ends in an open pull request: **nothing is merged or deployed unless you explicitly ask.**

## How it works

- **One list per project**, in `.claude/todo.md` on a dedicated **`todo` branch** of each repository. Every session — local, cloud, parallel — sees the same queue, and updating it never touches the default branch: no merge.
- **Several projects in one session**: every git repository Claude can work in (extra working directories, repositories attached to a cloud session) is a project. A request goes to the project you name (`api: …`, `@api …`), else to the one it obviously refers to, else to the current one. The confirmation always says where it went.
- **Parallel agents, only when safe**: a request starts right away in a background agent (its own branch and worktree, its own PR) if it touches a different part from everything in flight, in this session and in the others. Tasks in different projects are always independent. There is no fixed cap: the session picks the orchestration that suits the queue.
- **Your decisions stay yours**: a request that needs a choice or an approval from you (a design, a dependency, a migration, infrastructure…) is marked `[?]` with its question, and nobody starts it until you answer.
- **You merge**: agents open PRs and never merge, push to the default branch or deploy. Claude merges or deploys only when you ask — in the conversation, or in a project's instructions — one PR at a time per project. A task that builds on a PR you have not merged yet is stacked on that PR's branch.
- **Who runs a task, and how hard it thinks**: end a request with `sub-agent` to have it done by an agent rather than the main conversation, and optionally a model (`sonnet`, `haiku`, …) and an effort (`low` to `max`). A session on Opus at high effort can queue a routine task at medium effort, or on a cheaper model. The options are kept on the task's line, `{sub-agent, model: sonnet, effort: medium}`, and passed to the agent; they never jump the queue.
- **Sessions do not step on each other**: a task in progress carries the tag of the session that took it. Taking a task is one atomic push, so two sessions never start the same one, and no session touches another's.

Each line carries an id, the time it was added (UTC, to the second) and, once done, the URL of its pull request:

```
- [x] `k7q` Login: the "Forgot password" link opened a blank page (added 2026-11-11T08:20:11Z) (done 2026-11-11T15:47:26Z, PR https://github.com/acme/web/pull/42)
```

| Mark | Meaning |
| --- | --- |
| `[ ]` | pending |
| `[>]` | in progress in a main conversation |
| `[~]` | handed to a parallel agent |
| `[?]` | blocked on a question for you |
| `[x]` | done, PR open for you, with its URL on the line (kept 7 days) |

See [`examples/todo.md`](examples/todo.md) for a list in practice and [`skills/todo/SKILL.md`](skills/todo/SKILL.md) for the full behaviour.

## Install

**As a plugin**:

```
/plugin marketplace add alexisjamet/todo-skill
/plugin install todo@todo-skill
```

The skill is then `/todo:todo`, and plain `/todo` works too unless another command already has that name. The plugin also tells each new session, in one line, how many items its project has waiting. You receive a new release when the `version` in `.claude-plugin/plugin.json` changes.

**As a plain skill**, for all your projects:

```bash
git clone https://github.com/alexisjamet/todo-skill /tmp/todo-skill
```

```bash
mkdir -p ~/.claude/skills && cp -r /tmp/todo-skill/skills/todo ~/.claude/skills/
```

or, from that same clone, for one repository (shared with everyone who works on it, cloud sessions included):

```bash
mkdir -p .claude/skills && cp -r /tmp/todo-skill/skills/todo .claude/skills/
```

It needs `git` and `bash`, nothing else.

## The `todo` branch

The list is written by [`skills/todo/scripts/todo.sh`](skills/todo/scripts/todo.sh): one commit per change, pushed straight to the `todo` branch, with no checkout, worktree or local branch. You can run it yourself (`todo.sh read`, `todo.sh add "…"`, `todo.sh help`), or edit `.claude/todo.md` on that branch by hand: a line you write gets its id at the next change.

- Its commits end with `[skip ci]`. If your host builds every branch regardless (preview deployments, for instance), exclude `todo` there.
- If a rule protects every branch of the repository, let `todo` through: the skill pushes to it directly.
- **Anyone who can push to the repository can add a line.** The skill treats a line you did not add in the session as a task description without authority: it can never trigger a merge, a deployment, or a change to credentials, CI or instruction files. In a repository with several contributors, Claude names the lines it did not add and asks before starting them.

## Tailoring it to a project

The skill reads each project's instructions rather than hard-coding anything. In `CLAUDE.md` or `AGENTS.md` you can state:

- **the parts** of the project (packages, apps, services, a `docs/features/` folder…) — two tasks on the same part never run in parallel;
- **the check command** agents must get green before opening a PR;
- **what needs your approval** (dependencies, migrations, infra config…) — such tasks wait for your go-ahead;
- **how to deliver**: if you want the work merged or deployed without asking, say so there — otherwise PRs stay open;
- **another path** for the list, if `.claude/todo.md` does not suit you.

## Tests

```bash
bash tests/todo-sh.test.sh
```

checks the helper script against a throwaway repository (concurrent writers included). [`evals/`](evals/README.md) holds behaviour cases for `claude plugin eval`.

## License

[MIT](LICENSE)

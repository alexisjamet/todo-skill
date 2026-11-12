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

- **A queue that is yours alone.** It lives in a private page on claude.ai, the **Todo Queue**, which Claude creates the first time you use `/todo`. Nothing is written into your repositories: no file, no branch. Your teammates never see it.
- **One queue for all your sessions and projects.** Local or cloud, every session of yours reads and feeds the same queue. Each task names its project, so `/todo` shows them all.
- **A page you can use.** Open the Todo Queue on your computer or your phone to see what is pending, in progress or waiting for you, add a task, answer a question, reorder or remove.
- **Several projects in one session**: every git repository Claude can work in (extra working directories, repositories attached to a cloud session) is a project. A request goes to the project you name (`api: …`, `@api …`), else to the one it obviously refers to, else to the current one. The confirmation always says where it went.
- **Parallel agents, only when safe**: a request starts right away in a background agent (its own branch and worktree, its own PR) if it touches a different part from everything in flight, in this session and in your others. Tasks in different projects are always independent. There is no fixed cap: the session picks the orchestration that suits the queue.
- **Your decisions stay yours**: a request that needs a choice or an approval from you (a design, a dependency, a migration, infrastructure…) is marked `[?]` with its question, and nobody starts it until you answer, in the conversation or on the page.
- **You merge**: agents open PRs and never merge, push to the default branch or deploy. Claude merges or deploys only when you ask — in the conversation, or in a project's instructions — one PR at a time per project. A task that builds on a PR you have not merged yet is stacked on that PR's branch.
- **Who runs a task, and how hard it thinks**: end a request with `sub-agent` to have it done by an agent rather than the main conversation, and optionally a model (`sonnet`, `haiku`, …) and an effort (`low` to `max`). A session on Opus at high effort can queue a routine task at medium effort, or on a cheaper model. The options are kept on the task, `{sub-agent, model: sonnet, effort: medium}`, and passed to the agent; they never jump the queue.
- **Sessions do not step on each other**: a task in progress carries the tag of the session that took it. Taking a task is an atomic write, so two sessions never start the same one, and no session touches another's.

Claude shows each task as one line, with its id, the time it was added (UTC, to the second) and, once done, the URL of its pull request:

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

See [`examples/todo.md`](examples/todo.md) for a queue in practice and [`skills/todo/SKILL.md`](skills/todo/SKILL.md) for the full behaviour.

## Where the queue lives

**The Todo Queue artifact** is used whenever your session can publish [artifacts](https://code.claude.com/docs/en/artifacts): a session signed in to claude.ai on a Pro, Max, Team or Enterprise plan, in the CLI, the desktop app or the cloud.

- The page is private, and its data sits in a part of its database that only you can read. If you ever share the page, the people you share it with see their own empty queue, not yours.
- The first `/todo` asks you once to approve publishing the page.
- To let Claude update the queue without asking each time, add `ArtifactData` to `permissions.allow` in your [settings](https://code.claude.com/docs/en/settings).

**A local file** is the fallback when artifacts are not available (API key, Bedrock or Vertex, headless runs, artifacts turned off). The queue is then `todo.md` inside each repository's `.git` directory: never committed, shared by the clone's worktrees, private to the machine, and not visible from your other machines or from cloud sessions. [`skills/todo/scripts/todo.sh`](skills/todo/scripts/todo.sh) reads and writes it; it needs `git` and `bash`, nothing else.

Earlier versions kept the list on a `todo` branch of each repository. The skill imports what is still open there the first time it meets one, and tells you the branch can be deleted.

## Install

**As a plugin**:

```
/plugin marketplace add alexisjamet/todo-skill
/plugin install todo@todo-skill
```

The skill is then `/todo:todo`, and plain `/todo` works too unless another command already has that name. You receive a new release when the `version` in `.claude-plugin/plugin.json` changes.

**As a plain skill**, for all your projects:

```bash
git clone https://github.com/alexisjamet/todo-skill /tmp/todo-skill
```

```bash
mkdir -p ~/.claude/skills && cp -r /tmp/todo-skill/skills/todo ~/.claude/skills/
```

or, from that same clone, for one repository (shared with everyone who works on it, cloud sessions included — each person still gets their own queue):

```bash
mkdir -p .claude/skills && cp -r /tmp/todo-skill/skills/todo .claude/skills/
```

## Tailoring it to a project

The skill reads each project's instructions rather than hard-coding anything. In `CLAUDE.md` or `AGENTS.md` you can state:

- **the parts** of the project (packages, apps, services, a `docs/features/` folder…) — two tasks on the same part never run in parallel;
- **the check command** agents must get green before opening a PR;
- **what needs your approval** (dependencies, migrations, infra config…) — such tasks wait for your go-ahead;
- **how to deliver**: if you want the work merged or deployed without asking, say so there — otherwise PRs stay open.

## Tests

```bash
bash tests/todo-sh.test.sh
```

checks the helper script against a throwaway repository (concurrent writers included). [`evals/`](evals/README.md) holds behaviour cases for `claude plugin eval`.

## License

[MIT](LICENSE)

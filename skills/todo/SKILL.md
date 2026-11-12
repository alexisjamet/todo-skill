---
name: todo
description: Queue tasks for one or several projects without interrupting the current work, and run independent ones in parallel with background agents. Use when the user types /todo <task> (one or several tasks, for any project), /todo alone to see every project's list, or /todo <project> to see one. Adds each item to its project's to-do list, confirms in one line, starts parallel agents when tasks are independent of everything in flight, and carries on with what was under way. Work ends in open pull requests: nothing is merged or deployed unless the user explicitly asks.
---

# /todo — a task queue across projects, with parallel agents

The user sends `/todo …` **while** you work, so as not to interrupt you. This skill never makes you change subject: it records the request in the right project, starts work in parallel when that is safe, then you resume exactly where you were.

## Projects

A **project** is a git repository you can work in: the working directory, plus any other repository in this session (extra working directories, repositories attached to a cloud session). Name each one by its repository name (`owner/repo` only if two names clash). The project of the task under way is the **current project**.

### Where a project's list lives

Each project keeps its own list in `.claude/todo.md` (or another path its `CLAUDE.md` / `AGENTS.md` names), on a dedicated branch **`todo`** that holds nothing else. The list is shared by every session, local or cloud, and updating it never touches the default branch, so it needs no merge and triggers no deployment.

- **Read**: `git -C <project> fetch -q origin todo`, then `git -C <project> show origin/todo:.claude/todo.md`. No `todo` branch yet: read `origin/<default>:.claude/todo.md` if it exists (default branch from `git -C <project> symbolic-ref --short refs/remotes/origin/HEAD`), else start from `# To do`. Merge in whatever this session has on top: never lose a line.
- **Write**: as soon as a list changes, commit it on `todo` and push that branch — from a worktree of it outside the project's checkout (`git -C <project> worktree add <scratch dir>/todo-<project> todo`; if the branch does not exist, create it as an orphan holding only the list). Push rejected because another session wrote first: fetch, merge the lines, push again. This is the only push the skill makes without being asked.
- A project with no remote: the local file is the list.

### Routing a request to a project

For each request, in this order:
1. **Explicit**: `/todo <project>: …` or `/todo @<project> …` (case-insensitive; an unambiguous prefix of a repository name is enough).
2. **Inferred**: the request names something that only one project has (a file, a module, an app, a feature, a page, a domain…).
3. **Default**: the current project.

The one-line confirmation always says which project each item went to, so the user can correct a wrong guess with one word.

If the target project is not available in this session: in a cloud session, attach it if you have a tool for that (e.g. `add_repo`); otherwise keep the item in the current project's list under a `## For <project>` heading, say so in the confirmation, and move it to its own list the next time that project is open.

## Line format

- `- [ ] <request, briefly reworded without losing anything> (added YYYY-MM-DD)`: pending
- `- [~] … (agent <name>, branch <branch>)`: handed to a parallel agent
- `- [>] …`: in progress in the main conversation
- `- [x] … (done YYYY-MM-DD, PR #N)`: done, pull request open for the user (merged: `PR #N merged`)
- `- [?] … — question: …`: blocked on a question for the user

Useful detail (files, screenshots, URLs, follow-up messages) goes in sub-bullets. Write the lines in the user's language. `[x]` lines older than 7 days are deleted.

## `/todo` alone, or `/todo <project>`

Read each list (see above) and show it, grouped by project, current project first: in progress and handed off, pending, blocked, then done. Skip projects whose list is empty or missing, and say so in one line at the end. `/todo <project>` shows that project only. Nothing else.

## `/todo <requests>`

1. Route each request (see above) and add it to its project's list. Several requests in one message → several lines, possibly in several projects.
2. **Triage** each request: can it start in parallel right now? Only if both hold:
   - it touches a **different part** from the task under way and from every agent already running. Tasks in two different projects are always in different parts. Inside one project, the parts are those its instructions define (a `docs/features/` folder, packages of a monorepo, apps, services…); failing that, its top-level modules. Two requests on the same part never run at the same time;
   - it needs no **choice from the user** (alternatives to compare, a design to approve, an open question), and nothing the project's instructions reserve for the user's approval: a dependency, a schema or data migration, infrastructure or deployment config, an architecture change, anything irreversible or outward-facing.
3. **Orchestrate** what passes the triage as suits the work: there is no fixed limit on agents. One agent per task by default; small related tasks on the same part can share one agent and one PR only if the user grouped them; a task that depends on another waits for it. Start each agent with the `Agent` tool (`run_in_background: true`, short meaningful name) and the brief below, and mark its line `[~]`. For the current project use `isolation: "worktree"`; for another project, the brief tells the agent to create its own worktree. What does not pass stays `[ ]`.
4. Answer in **one line**: "Noted in <project> (N pending, M in parallel)." or "Noted in <project>, started in parallel (agent <name>)." — several projects: "Noted: 2 in api, 1 in web (agent web-footer)." No further analysis.
5. **Resume the task under way** unchanged, unless the new request directly contradicts it (say so in one sentence and follow the most recent request).

### Brief for a parallel agent

It knows only what you write. Give it:
- the user's exact request, word for word, with its sub-bullets;
- the project (absolute path of its checkout) and the part concerned, with the files to read first: the project's `CLAUDE.md` / `AGENTS.md` (root and in the folder it works in) and the part's own doc if the project has one;
- where to work: a branch `claude/<short topic>` from an up-to-date `origin/<default>`, in its own worktree — for another project, `git -C <project> worktree add <scratch dir>/<branch> -b <branch> origin/<default>` — never in a checkout the main conversation uses;
- the rules: do the task completely, tests included; update the project's docs as its instructions require; run the project's check command (from its instructions, else its `package.json` scripts, `Makefile`, CI config…) until green; commit, push **its own branch** and **open the PR — never merge it, never push to the default branch, never deploy**; never touch the to-do list;
- if it hits a choice that belongs to the user: do not decide, push what is done, and say so in its report;
- its final report, short: PR number, what changed, what it could not do, any questions.

## When an agent reports back

Between two steps of your own task:
1. Rebase its branch on `origin/<default>`, resolve conflicts, rerun the check, push the branch.
2. Mark the line `[x]` with the PR number, and list the PR in your next report.
3. If it raised a question: `[?]` line, question asked to the user in your next report.
4. An agent finished: rerun the triage on the `[ ]` lines of every project, oldest first.

## When your own task is done

1. Open its PR and mark it `[x]` with the PR number.
2. Take the oldest `[ ]` line that does not touch a part handed to an agent — in the current project first, then in the others — mark it `[>]`, announce it in one line ("Next (<project>): … (N left)") and start it right away, without waiting for confirmation. Before that, rerun the triage: other lines may start in parallel.
3. A request too ambiguous to do safely: `[?]` with the question, and move on to the next one. Ask all the questions at the end.
4. Every list empty and no agent running: say so in one line in the final report, with the PRs left open for the user.

## Merging and deploying

**Never**, unless the user explicitly asks — in the conversation, or in a project's instructions (`CLAUDE.md`, `AGENTS.md`) that say the work is merged or deployed without asking. A request to merge covers the PRs it names, nothing more. When merging, go **one PR at a time per project**: rebase, rerun the check, merge, then deploy only if that was asked too (two deployments at once can put an older default branch back in production). Mark the line `PR #N merged`.

## Rules

- Lists are changed only by the main conversation, and only on the `todo` branch.
- A pending request never justifies interrupting, shortening or half-finishing the task under way.
- Each request is a separate task: its own branch, its own PR.

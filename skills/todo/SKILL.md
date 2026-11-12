---
name: todo
description: Queue tasks for one or several projects without interrupting the current work, and run independent ones in parallel with background agents. Use when the user types /todo <task> (one or several tasks, for any project), /todo alone to see every project's list, or /todo <project> to see one. Adds each item to its project's to-do list read from that project's default branch, confirms in one line, starts a parallel agent when a task is independent of everything in flight, and carries on with what was under way.
---

# /todo — a task queue across projects, with parallel agents

The user sends `/todo …` **while** you work, so as not to interrupt you. This skill never makes you change subject: it records the request in the right project, starts part of the queue in parallel when that is safe, then you resume exactly where you were.

## Projects

A **project** is a git repository you can work in: the working directory, plus any other repository in this session (extra working directories, repositories attached to a cloud session). Name each one by its repository name (`owner/repo` only if two names clash). The project of the task under way is the **current project**.

Each project keeps its own list, by default in `.claude/todo.md` at its root. If the project's instructions (`CLAUDE.md`, `AGENTS.md`) name another path, use that one.

### The list is authoritative on the default branch

Every session starts from its own copy of each repository, so a local list can be stale. **Before reading or writing a project's list**, run `git -C <project> fetch -q origin <default>` (default branch from `git -C <project> symbolic-ref --short refs/remotes/origin/HEAD`, else `main`) and start from `git -C <project> show origin/<default>:<list path>`. If the file does not exist yet, start from `# To do`. Merge in whatever the local copy has on top (lines added in this session, not merged yet): never lose a line. A project with no remote: the local file is the truth.

### Routing a request to a project

For each request, in this order:
1. **Explicit**: `/todo <project>: …` or `/todo @<project> …` (case-insensitive, unambiguous prefix of a repository name is enough).
2. **Inferred**: the request names something that only one project has (a file, a module, an app, a feature, a page, a domain…).
3. **Default**: the current project.

The one-line confirmation always says which project each item went to, so the user can correct a wrong guess with one word.

If the target project is not available in this session: in a cloud session, attach it if you have a tool for that (e.g. `add_repo`); otherwise keep the item in the current project's list under a `## For <project>` heading, say so in the confirmation, and move it to its own list the next time that project is open.

## Line format

- `- [ ] <request, briefly reworded without losing anything> (added YYYY-MM-DD)`: pending
- `- [~] … (agent <name>, branch <branch>)`: handed to a parallel agent
- `- [>] …`: in progress in the main conversation
- `- [x] … (done YYYY-MM-DD, PR #N)`: delivered (commit hash if the project has no PRs)
- `- [?] … — question: …`: blocked on a question for the user

Useful detail (files, screenshots, URLs, follow-up messages) goes in sub-bullets. Write the lines in the user's language. `[x]` lines older than 7 days are deleted.

## `/todo` alone, or `/todo <project>`

Read each list from its default branch (see above) and show it, grouped by project, current project first: in progress and handed off, pending, blocked, then delivered. Skip projects whose list is empty or missing, and say so in one line at the end. `/todo <project>` shows that project only. Nothing else.

## `/todo <requests>`

1. Route each request (see above) and add it to its project's list. Several requests in one message → several lines, possibly in several projects.
2. **Triage** each request: can it start in parallel right now? Only if **all** of these hold:
   - it touches a **different part** from the task under way and from every agent already running. Tasks in two different projects are always in different parts. Inside one project, the parts are those its instructions define (a `docs/features/` folder, packages of a monorepo, apps, services…); failing that, its top-level modules. Two requests on the same part never run at the same time;
   - it needs no **choice from the user** (alternatives to compare, a design to approve, an open question), and nothing the project's instructions reserve for the user's approval: a dependency, a schema or data migration, infrastructure or deployment config, an architecture change, anything irreversible or outward-facing;
   - **fewer than 3 agents** are running across all projects (unless the user set another limit).
3. If so: start a background agent (`Agent` tool, `run_in_background: true`, short meaningful name) with the brief below, and mark the line `[~]`. For the current project use `isolation: "worktree"`; for another project, the brief tells the agent to create its own worktree of that repository. Otherwise the line stays `[ ]`.
4. Answer in **one line**: "Noted in <project> (N pending, M in parallel)." or "Noted in <project>, started in parallel (agent <name>)." — several projects: "Noted: 2 in api, 1 in web (agent web-footer)." No further analysis.
5. **Resume the task under way** unchanged, unless the new request directly contradicts it (say so in one sentence and follow the most recent request).

### Brief for a parallel agent

It knows only what you write. Give it:
- the user's exact request, word for word, with its sub-bullets;
- the project (absolute path of its checkout) and the part concerned, with the files to read first: the project's `CLAUDE.md` / `AGENTS.md` (root and in the folder it works in) and the part's own doc if the project has one;
- where to work: a branch `claude/<short topic>` from an up-to-date `origin/<default>`, in its own worktree — for another project, `git -C <project> worktree add <scratch dir>/<branch> -b <branch> origin/<default>` — never in a checkout the main conversation uses;
- the rules: do the task completely, tests included; update the project's docs as its instructions require; run the project's check command (from its instructions, else its `package.json` scripts, `Makefile`, CI config…) until green; commit, push, **open the PR, without merging or deploying** (no PRs in this project: push the branch); never touch the to-do list;
- if it hits a choice that belongs to the user: do not decide, push what is done, and say so in its report;
- its final report, short: PR number, what changed, what it could not do, any questions.

## When an agent reports back

The main conversation, and only it, integrates and delivers, **one PR at a time per project** (two deliveries in parallel can put an older default branch back in production). Between two steps of your own task:
1. Rebase its branch on `origin/<default>`, resolve conflicts, rerun the check, push.
2. Then deliver as the project's instructions say (merge, then deploy unless the user said not to). If they say nothing about merging, leave the PR open and list it in your next report. Mark the line `[x]` with the PR number.
3. If it raised a question: `[?]` line, question asked to the user in your next report.
4. A slot is free: rerun the triage on the `[ ]` lines of every project, oldest first.

## When your own task is delivered

1. Mark it `[x]` (with the PR number).
2. Take the oldest `[ ]` line that does not touch a part handed to an agent — in the current project first, then in the others — mark it `[>]`, announce it in one line ("Next (<project>): … (N left)") and start it right away, without waiting for confirmation. Before that, rerun the triage: other lines may start in parallel.
3. A request too ambiguous to do safely: `[?]` with the question, and move on to the next one. Ask all the questions at the end.
4. Every list empty and no agent running: say so in one line in the final report.

## Rules

- Lists are changed only by the main conversation. A project's list changes ride with the commit of the next task delivered in that project (no separate commit just for an added line). If no delivery is coming in a project whose list changed, commit the list on its own before your final report — as the project's instructions allow, else in a small PR `todo: update list` — so nothing is lost when the session ends.
- A pending request never justifies interrupting, shortening or half-delivering the task under way.
- Each request is a separate task: its own branch, its own PR, its own delivery.

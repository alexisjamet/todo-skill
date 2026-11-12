# Changelog

Releases are tagged `vX.Y.Z`, and the same number is the `version` in `.claude-plugin/plugin.json`: plugin users receive a release when it changes. Versions follow [semantic versioning](https://semver.org): a major version changes where the queue lives or how it is written, a minor one adds behaviour, a patch fixes.

## 2.0.1 — 2026-11-12

### Fixed

- The frontmatter of `SKILL.md` was not valid YAML: its description held an unquoted `: `. Claude Code loaded it all the same, but strict parsers refused it, GitHub's preview among them. The description and `allowed-tools` are now quoted strings.
- The description held angle brackets (`/todo <task>`), which claude.ai reports as XML tags when it syncs the plugin and strips from the text it stores. It now says the same thing in words.

## 2.0.0 — 2026-11-12

The queue becomes personal and leaves the repositories.

### Changed

- The queue lives in the **Todo Queue**, a private claude.ai artifact with its own database, readable by its user alone and shared by all of their sessions. Its page lets them add a task, answer a question, reorder, remove, and free a task held by a dead session.
- Nothing is written into a repository any more: the `todo` branch, its push and the `## For <project>` sections are gone. A project that still has a `todo` branch gets its open lines imported once.
- A request that needs the user's choice or approval is blocked with its question instead of being started later without asking.
- A queued task that asks for a merge or a deployment waits for the user's confirmation in the conversation.
- Run options are recognised only at the end of a request or in braces.
- An agent's branch is no longer rebased when it reports back; rebasing belongs to merging, with `--force-with-lease`.

### Added

- Each task has a short id, the UTC time it was added and was done, to the second, and the full URL of its pull request.
- A task in progress carries the tag of the session that took it. Taking a task is atomic: two sessions never start the same one.
- Stacked work: a task that builds on an unmerged pull request branches from it.
- `/todo first <id>` and `/todo drop <id>`.
- A task that changes no code ends with `no PR: <result>`.
- `skills/todo/scripts/todo.sh`: the queue as a local file in the git directory, for sessions without artifacts.
- Tests for the helper script, and eval cases for `claude plugin eval`.

### Fixed

- Writing the list failed when the `todo` branch did not exist yet, on a second `/todo` in a session, and with two sessions in one clone.
- The default branch was not found when `origin/HEAD` was not set.
- An agent could create a second worktree inside the one it was given.
- Forks were ruled out for a task with a model, but not for one with an effort.

## 1.1.0 — 2026-11-12

- A task can say who runs it: `sub-agent`, a model, an effort.

## 1.0.0 — 2026-11-12

- First version: a `/todo` queue across projects, with parallel agents; lists on a `todo` branch; nothing merged or deployed unless asked.

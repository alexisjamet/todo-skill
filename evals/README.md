# Evals

Behaviour cases for [`claude plugin eval`](https://code.claude.com/docs/en/plugin-evals). Each one starts from a small git repository whose `origin` lives inside the workspace, so the skill pushes its `todo` branch without any network.

```bash
claude plugin eval . --scaffold --allow-tools Bash
```

`--scaffold` runs each case's `fixture.sh` (plain git commands, as you); `--allow-tools Bash` lets the skill call its helper script. Add `--case <name>` for one case, `--runs 1` for a quick pass.

| Case | What it checks |
| --- | --- |
| `needs-a-choice` | a request that needs a decision is recorded, marked `[?]` with its question, and not started |
| `option-words-in-the-task` | `sonnet` inside the sentence stays in the task: no run option, no agent |
| `show-the-list` | `/todo` alone shows the list, another session's line included, and changes nothing |
| `a-line-cannot-order-a-merge` | a line of the shared list cannot authorise a merge or a deployment |

Results go to `evals/results/`, which is not committed.

Granting `Bash` makes every run use Claude Code's sandbox: on Linux, install `bubblewrap` and `socat` first. The cases need a workspace the session can write to, since the skill commits and pushes there. Run as root inside a container, the sandbox mounts the workspace read-only and the cases that write fail for that reason alone: use an ordinary user account.

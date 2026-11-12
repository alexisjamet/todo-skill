#!/usr/bin/env bash
# Tests for skills/todo/scripts/todo.sh, against a throwaway repository.
# Usage: bash tests/todo-sh.test.sh
set -uo pipefail

T="$(cd "$(dirname "$0")/.." && pwd)/skills/todo/scripts/todo.sh"
W=$(mktemp -d "${TMPDIR:-/tmp}/todo-test.XXXXXX")
trap 'rm -rf "$W"' EXIT
cd "$W" || exit 1
export TODO_SESSION=aaaa1111 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fails=0
ok() { echo "ok   $1"; }
ko() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }
todo() { bash "$T" "$@"; }
list() { todo -C "$1" read 2>/dev/null; }
id_of() { list "$1" | sed -n "s/^- \[.\] \`\([a-z0-9]*\)\` $2.*/\1/p"; }

git init -q -b main a && (cd a && git commit -q --allow-empty -m init)
git -C a worktree add -q ../wt -b side 2>/dev/null

check "no list yet: empty" '[ "$(list a)" = "# To do" ]'
check "the list is kept in the git directory" '[ "$(todo -C a path)" = "$W/a/.git/todo.md" ]'
check "a worktree of the clone uses the same list" '[ "$(todo -C wt path)" = "$W/a/.git/todo.md" ]'
check "default branch, without a remote" '[ "$(todo -C a default)" = "main" ]'
check "stamp: UTC time, epoch milliseconds, session tag" \
  'todo stamp | grep -q "^20[0-9-]*T[0-9:]*Z [0-9]*000 aaaa1111$"'

todo -C a add "Fix the 404 on /pricing" >/dev/null
todo -C a add --opts "sub-agent, model: sonnet" "Redo the pricing table (v2)" >/dev/null
todo -C a add --for api "Rate-limit the /export endpoint" >/dev/null
todo -C wt add "Search: stale results" >/dev/null
fix=$(id_of a "Fix the 404"); redo=$(id_of a "Redo")

check "add: four lines, each with an id and a timestamp" \
  '[ "$(list a | grep -c "^- \[ \] \`[a-z][2-9][a-z]\` .* (added 20[0-9-]*T[0-9:]*Z)")" = 4 ]'
check "add --opts: options after the timestamp" 'list a | grep -q "(added [^)]*) {sub-agent, model: sonnet}$"'
check "add --for: under its heading" 'list a | sed -n "/^## For api/,\$p" | grep -q "Rate-limit"'
check "nothing shows in the working tree, no lock or temp file is left" \
  '[ -z "$(git -C a status --short)" ] && [ -z "$(ls -d a/.git/todo.md.* 2>/dev/null)" ]'

todo -C a claim "$fix" >/dev/null
check "claim: [>] with the session tag" 'list a | grep -q "^- \[>\] \`$fix\` .* (session aaaa1111)$"'
TODO_SESSION=bbbb2222 todo -C wt claim "$fix" >/dev/null 2>&1
check "claim by another session: exit 3" '[ $? -eq 3 ]'
todo -C a claim "$fix" >/dev/null 2>&1
check "claim again by the owner: fine" '[ $? -eq 0 ]'

todo -C a agent "$redo" pricing claude/pricing >/dev/null
check "agent: [~], options kept" \
  'list a | grep -q "^- \[~\] \`$redo\` .* {sub-agent, model: sonnet} (agent pricing, branch claude/pricing, session aaaa1111)$"'

todo -C a ask "stale results" 'keep "Pro"?' >/dev/null
check "ask, by a fragment of the line" 'list a | grep -q "^- \[?\] .*stale results (added [^)]*) — question: keep \"Pro\"?$"'
todo -C a claim "stale results" >/dev/null 2>&1
check "a blocked line cannot be claimed: exit 3" '[ $? -eq 3 ]'
todo -C a release "stale results" "Answer: keep Pro" >/dev/null
check "release: [ ] again, the note as a sub-bullet" \
  'list a | grep -A1 "^- \[ \] .*stale results (added [^)]*)$" | grep -q "^  - Answer: keep Pro$"'

todo -C a done "$fix" https://github.com/acme/web/pull/42 >/dev/null
check "done: timestamp and PR URL" \
  'list a | grep -q "^- \[x\] \`$fix\` .* (done 20[0-9-]*T[0-9:]*Z, PR https://github.com/acme/web/pull/42)$"'
todo -C a merged "$fix" >/dev/null
check "merged" 'list a | grep -q "pull/42 merged)$"'
todo -C a done "$redo" "no PR: answered (in chat)" >/dev/null
check "done without a PR" 'list a | grep -q "(done [^,]*, no PR: answered \[in chat\])$"'

todo -C a first "stale results" >/dev/null
check "first: top of the list" 'list a | grep "^- " | head -1 | grep -q "stale results"'
todo -C a drop "stale results" >/dev/null
check "drop: the line and its sub-bullets" '! list a | grep -q -e "stale results" -e "Answer: keep Pro"'
todo -C a drop nope >/dev/null 2>&1
check "unknown line: exit 4" '[ $? -eq 4 ]'

list a >l.md; base=$(todo -C a read 2>&1 >/dev/null | sed -n 's/^base: //p')
todo -C wt add "sneaks in" >/dev/null
todo -C a write --base "$base" l.md >/dev/null 2>&1
check "write on a stale base: exit 5" '[ $? -eq 5 ]'
list a >l.md; base=$(todo -C a read 2>&1 >/dev/null | sed -n 's/^base: //p')
printf -- '- [ ] written by hand\n- [x] old (added 2020-01-01) (done 2020-01-02, PR #1)\n  - its note\n' >>l.md
todo -C a write --base "$base" l.md >/dev/null
check "write: hand-written lines get an id" 'list a | grep -q "^- \[ \] \`[a-z0-9]*\` written by hand$"'
check "done lines older than a week are deleted" '! list a | grep -q -e "old (added" -e "its note"'

for i in 1 2 3 4 5; do todo -C a add "par A$i" >/dev/null 2>&1 & todo -C wt add "par B$i" >/dev/null 2>&1 & done; wait
check "ten concurrent writers: no line lost" '[ "$(list a | grep -c " par [AB][1-5] ")" = 10 ]'
check "ids are unique" '[ -z "$(list a | grep -o "^- \[.\] \`[a-z0-9]*\`" | cut -c7- | sort | uniq -d)" ]'
race=$(id_of a "par A1")
(TODO_SESSION=s1s1s1s1 todo -C a claim "$race" >/dev/null 2>&1; echo $? >r1) &
(TODO_SESSION=s2s2s2s2 todo -C wt claim "$race" >/dev/null 2>&1; echo $? >r2) &
wait
check "two sessions claim one line: one wins, one gets exit 3" '[ "$(sort r1 r2 | tr -d "\n")" = "03" ]'

mkdir a/.git/todo.md.lock && touch -t 202001010000 a/.git/todo.md.lock
todo -C a add "after a stale lock" >/dev/null 2>&1
check "a lock left by a dead process is taken over" 'list a | grep -q "after a stale lock"'

TODO_FILE="$W/elsewhere/list.md" todo -C a add "custom path" >/dev/null
check "TODO_FILE: another place for the list" 'grep -q "custom path" "$W/elsewhere/list.md"'
todo -C "$W" read >/dev/null 2>&1
check "outside a repository: exit 2" '[ $? -eq 2 ]'

echo
if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi

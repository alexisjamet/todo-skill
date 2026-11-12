#!/usr/bin/env bash
# todo.sh — read and change a project's to-do list on its `todo` branch.
#
# The list is one file (.claude/todo.md, or $TODO_FILE) on a branch that holds
# nothing else. Every change is one commit pushed straight to that branch: no
# checkout, no worktree, no local branch. A change is re-applied on the latest
# list when another session pushed first, so two sessions never lose a line and
# never both take the same task. With no `origin` remote the branch is local.
#
# Usage: todo.sh [-C <repo>] <command> [args]
#
#   read                         print the list (stderr: base commit, writers;
#                                offline, the last copy fetched, marked stale)
#   add [--for <project>] [--opts "<run options>"] <text>
#   claim <id>                   [>] taken by this session
#   agent <id> <name> <branch>   [~] handed to an agent of this session
#   done <id> <PR URL | no PR: result>
#   merged <id>                  the done line's PR was merged
#   ask <id> <question>          [?] blocked on a question
#   release <id> [note]          back to [ ]; the note becomes a sub-bullet
#   note <id> <text>             add a sub-bullet
#   first <id>                   move to the top of its section
#   drop <id>                    remove the line and its sub-bullets
#   write --base <commit|none> <file>   replace the whole list (see read)
#   default                      print the default branch
#   session                      print this session's tag
#   hook                         one line for a SessionStart hook
#
# <id> is the line's id, or a fragment of text found in exactly one line.
# Exit codes: 0 ok, 2 git or network, 3 the task is taken, 4 no such line,
# 5 the list changed since it was read, 64 usage.
#
# Environment: TODO_FILE (list path), TODO_SESSION (session tag, else taken
# from CLAUDE_CODE_SESSION_ID), TODO_COMMIT_TRAILER (text appended to commit
# messages).

set -euo pipefail
export GIT_TERMINAL_PROMPT=0 LC_ALL=C

repo=.
while [ $# -gt 0 ]; do
  case "$1" in
    -C) [ $# -ge 2 ] || { echo "todo.sh: -C needs a path" >&2; exit 64; }; repo=$2; shift 2 ;;
    *) break ;;
  esac
done
cmd=${1:-read}
[ $# -gt 0 ] && shift

LIST=${TODO_FILE:-.claude/todo.md}
TIP=""
tmp=""
trap '[ -z "$tmp" ] || rm -rf "$tmp"' EXIT

die() { local code=$1; shift; echo "todo.sh: $*" >&2; exit "$code"; }
usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-64}"; }
g() { git -C "$repo" "$@"; }
has_remote() { g remote get-url origin >/dev/null 2>&1; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
cutoff() { date -u -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -u -v-7d +%Y-%m-%d; }
one_line() { printf '%s' "$*" | tr '\n\r\t' '   '; }

# Temporary files, only for commands that write. A sandboxed session may have
# a read-only \$TMPDIR: the repository's git directory is then the fallback.
mktmp() {
  local gd
  [ -z "$tmp" ] || return 0
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/todo.XXXXXX" 2>/dev/null) && return 0
  gd=$(g rev-parse --absolute-git-dir 2>/dev/null) || die 2 "not a git repository: $repo"
  tmp=$(mktemp -d "$gd/todo-tmp.XXXXXX" 2>/dev/null) || die 2 "no writable place for temporary files"
}

session_tag() {
  local s=${TODO_SESSION:-${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}}
  s=${s#session_}
  printf '%s' "${s:0:8}"
}

default_branch() {
  local b
  if b=$(g symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s\n' "${b#origin/}"; return 0
  fi
  if has_remote; then
    b=$(g ls-remote --symref origin HEAD 2>/dev/null | awk '$1 == "ref:" { sub("refs/heads/", "", $2); print $2; exit }') || b=""
    if [ -n "$b" ]; then printf '%s\n' "$b"; return 0; fi
    for b in main master; do
      if g rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null 2>&1; then printf '%s\n' "$b"; return 0; fi
    done
  fi
  g symbolic-ref -q --short HEAD 2>/dev/null
}

# Sets TIP to the todo branch's commit, or "" when the branch does not exist.
# The fetch lands in a ref of this process alone: two sessions in the same
# clone would otherwise fight over the lock of origin/todo.
sync_tip() {
  local err ref="refs/todo-sync/$$"
  TIP=""
  if has_remote; then
    if err=$(g fetch -q --refmap= origin "+refs/heads/todo:$ref" 2>&1); then
      TIP=$(g rev-parse "$ref")
      g update-ref -d "$ref" >/dev/null 2>&1 || true
      g update-ref refs/remotes/origin/todo "$TIP" >/dev/null 2>&1 || true
    elif printf '%s' "$err" | grep -q "couldn't find remote ref"; then
      TIP=""
    elif [ -n "${TODO_STALE_OK:-}" ] && TIP=$(g rev-parse -q --verify refs/remotes/origin/todo 2>/dev/null); then
      echo "stale: could not fetch the todo branch, this is the last copy fetched ($(printf '%s' "$err" | head -1))" >&2
    else
      die 2 "cannot fetch the todo branch: $err"
    fi
  else
    TIP=$(g rev-parse -q --verify refs/heads/todo 2>/dev/null) || TIP=""
  fi
}

# Prints the list at TIP. No todo branch yet: the default branch's copy if it
# has one (lists written before the todo branch existed), else an empty list.
load_list() {
  local d
  if [ -n "$TIP" ]; then
    if g cat-file -e "$TIP:$LIST" 2>/dev/null; then g show "$TIP:$LIST"; else printf '# To do\n'; fi
    return 0
  fi
  if has_remote; then
    d=$(default_branch) || d=""
    if [ -n "$d" ] && g cat-file -e "refs/remotes/origin/$d:$LIST" 2>/dev/null; then
      g show "refs/remotes/origin/$d:$LIST"; return 0
    fi
  fi
  printf '# To do\n'
}

# commit_list <file> <subject>: one commit on top of TIP, pushed to the todo
# branch. Returns 1 when the push is refused (push output in $tmp/push.err).
commit_list() {
  local file=$1 subject=$2 blob idx tree commit msg
  mktmp
  blob=$(g hash-object -w -- "$file")
  idx="$tmp/index"; rm -f "$idx"
  if [ -n "$TIP" ]; then GIT_INDEX_FILE="$idx" git -C "$repo" read-tree "$TIP"; fi
  GIT_INDEX_FILE="$idx" git -C "$repo" update-index --add --cacheinfo "100644,$blob,$LIST"
  tree=$(GIT_INDEX_FILE="$idx" git -C "$repo" write-tree)
  if [ -z "$(g config user.email 2>/dev/null || true)" ] && [ -z "${GIT_AUTHOR_EMAIL:-}" ]; then
    export GIT_AUTHOR_NAME=todo GIT_AUTHOR_EMAIL=todo@localhost
    export GIT_COMMITTER_NAME=todo GIT_COMMITTER_EMAIL=todo@localhost
  fi
  msg="$subject [skip ci]"
  if [ -n "${TODO_COMMIT_TRAILER:-}" ]; then msg="$msg

$TODO_COMMIT_TRAILER"; fi
  if [ -n "$TIP" ]; then commit=$(g commit-tree "$tree" -p "$TIP" -m "$msg"); else commit=$(g commit-tree "$tree" -m "$msg"); fi
  if has_remote; then
    g push -q origin "$commit:refs/heads/todo" >"$tmp/push.err" 2>&1 || return 1
    g update-ref refs/remotes/origin/todo "$commit" >/dev/null 2>&1 || true
  else
    g update-ref refs/heads/todo "$commit" "$TIP" 2>"$tmp/push.err" || return 1
  fi
  TIP=$commit
}

# Reads a list on stdin, applies TODO_OP, prints the new list. The changed line
# goes to $TODO_REPORT. Exits 3 (taken) or 4 (no such line) with the reason on
# stderr.
transform() {
  local rc=0
  mktmp
  awk '
function isTask(l) { return l ~ /^- \[.\] / }
function markOf(l) { return substr(l, 4, 1) }
function idOf(l) {
  if (match(l, /^- \[.\] `[a-z0-9]+` /)) return substr(l, 8, RLENGTH - 9)
  return ""
}
function newId(   k) {
  do {
    k = substr(LET, int(rand() * length(LET)) + 1, 1) substr(DIG, int(rand() * length(DIG)) + 1, 1) substr(LET, int(rand() * length(LET)) + 1, 1)
  } while (k in used)
  used[k] = 1
  return k
}
# The line without its status tail: everything up to "(added ...)" and the run
# options that may follow it.
function baseOf(l,   i, j, p, e, rest) {
  p = 0; i = 1
  while ((j = index(substr(l, i), "(added ")) > 0) { p = i + j - 1; i = p + 1 }
  if (p) {
    j = index(substr(l, p), ")")
    if (j) {
      e = p + j - 1
      rest = substr(l, e + 1)
      if (match(rest, /^ [{][^}]*[}]/)) e += RLENGTH
      return substr(l, 1, e)
    }
  }
  sub(/ \((session|agent|done) [^)]*\)$/, "", l)
  sub(/ \342\200\224 question: .*$/, "", l)
  return l
}
function blockEnd(i,   j) {
  j = i
  while (j + 1 <= n && !del[j + 1] && line[j + 1] ~ /^[ \t]+[^ \t]/) j++
  return j
}
function dropBlock(i,   j, e) { e = blockEnd(i); for (j = i; j <= e; j++) del[j] = 1 }
function doneDate(l) {
  if (match(l, /\(done [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) return substr(l, RSTART + 6, 10)
  return ""
}
function find(key,   i, hit, c) {
  for (i = 1; i <= n; i++) if (!del[i] && isTask(line[i]) && idOf(line[i]) == key) return i
  c = 0
  for (i = 1; i <= n; i++) if (!del[i] && isTask(line[i]) && index(line[i], key) > 0) { hit = i; c++ }
  if (c == 1) return hit
  if (c > 1) fail(4, "\"" key "\" matches " c " lines: use an id")
  else fail(4, "no line matches \"" key "\"")
  return 0
}
function fail(code, why) { print "todo.sh: " why > "/dev/stderr"; rc = code }
function setLine(i, mark, tail) { line[i] = "- [" mark "] " substr(baseOf(line[i]), 7) tail; report = line[i] }
function mine(l) { return SESSION != "" && index(l, "session " SESSION ")") > 0 }
function takeable(i,   m) {
  m = markOf(line[i])
  if (m == " ") return 1
  if ((m == ">" || m == "~") && mine(line[i])) return 1
  if (m == ">" || m == "~") fail(3, "taken by another session: " line[i])
  else if (m == "x") fail(3, "already done: " line[i])
  else fail(3, "blocked on a question, release it first: " line[i])
  return 0
}
function addNote(i, text,   e) { e = blockEnd(i); ins[e] = ins[e] "  - " text "\n" }
function sectionStart(i,   j) { for (j = i; j >= 1; j--) if (line[j] ~ /^#/) return j; return 0 }

BEGIN {
  OP = ENVIRON["TODO_OP"]; KEY = ENVIRON["TODO_ID"]; TEXT = ENVIRON["TODO_TEXT"]
  OPTS = ENVIRON["TODO_OPTS"]; FOR = ENVIRON["TODO_FOR"]; SESSION = ENVIRON["TODO_SESSION_TAG"]
  NAME = ENVIRON["TODO_AGENT"]; BRANCH = ENVIRON["TODO_BRANCH"]
  NOW = ENVIRON["TODO_NOW"]; CUTOFF = ENVIRON["TODO_CUTOFF"]; REPORT = ENVIRON["TODO_REPORT"]
  LET = "abcdefghjkmnpqrstuvwxyz"; DIG = "23456789"
  srand(ENVIRON["TODO_SEED"] + 0)
  rc = 0; report = ""
}
{ sub(/\r$/, ""); line[++n] = $0 }
END {
  # Every task has an id; done lines older than a week go.
  for (i = 1; i <= n; i++) { k = idOf(line[i]); if (k != "") used[k] = 1 }
  for (i = 1; i <= n; i++)
    if (isTask(line[i]) && idOf(line[i]) == "") line[i] = substr(line[i], 1, 6) "`" newId() "` " substr(line[i], 7)
  for (i = 1; i <= n; i++)
    if (!del[i] && isTask(line[i]) && markOf(line[i]) == "x" && doneDate(line[i]) != "" && doneDate(line[i]) < CUTOFF) dropBlock(i)

  if (OP == "add") {
    new = "- [ ] `" newId() "` " TEXT " (added " NOW ")" (OPTS != "" ? " {" OPTS "}" : "")
    report = new
    if (FOR == "") {
      end = n
      for (i = 1; i <= n; i++) if (line[i] ~ /^## /) { end = i - 1; break }
      p = 0
      for (i = 1; i <= end; i++) if (!del[i] && line[i] !~ /^[ \t]*$/) p = i
      if (p == 0) ins[0] = ins[0] "# To do\n\n" new "\n"
      else ins[p] = ins[p] (line[p] ~ /^#/ ? "\n" : "") new "\n"
    } else {
      h = 0
      for (i = 1; i <= n; i++) if (tolower(line[i]) == tolower("## For " FOR)) { h = i; break }
      if (!h) ins[n] = ins[n] "\n## For " FOR "\n\n" new "\n"
      else {
        end = n
        for (i = h + 1; i <= n; i++) if (line[i] ~ /^## /) { end = i - 1; break }
        p = h
        for (i = h + 1; i <= end; i++) if (!del[i] && line[i] !~ /^[ \t]*$/) p = i
        ins[p] = ins[p] (p == h ? "\n" : "") new "\n"
      }
    }
  } else if (OP != "none") {
    i = find(KEY)
    if (i) {
      if (OP == "claim") { if (takeable(i)) setLine(i, ">", " (session " SESSION ")") }
      else if (OP == "agent") { if (takeable(i)) setLine(i, "~", " (agent " NAME ", branch " BRANCH ", session " SESSION ")") }
      else if (OP == "done") {
        gsub(/\(/, "[", TEXT); gsub(/\)/, "]", TEXT)
        setLine(i, "x", " (done " NOW ", " (TEXT ~ /^https?:\/\// ? "PR " TEXT : TEXT) ")")
      }
      else if (OP == "merged") {
        if (markOf(line[i]) != "x" || line[i] !~ /\)$/) fail(4, "not a done line: " line[i])
        else if (line[i] !~ / merged\)$/) { line[i] = substr(line[i], 1, length(line[i]) - 1) " merged)"; report = line[i] }
        else report = line[i]
      }
      else if (OP == "ask") setLine(i, "?", " \342\200\224 question: " TEXT)
      else if (OP == "release") { setLine(i, " ", ""); if (TEXT != "") addNote(i, TEXT) }
      else if (OP == "note") { addNote(i, TEXT); report = line[i] }
      else if (OP == "drop") { report = line[i]; dropBlock(i) }
      else if (OP == "first") {
        report = line[i]
        s = sectionStart(i); f = 0
        for (j = s + 1; j <= n; j++) if (!del[j] && isTask(line[j])) { f = j; break }
        if (f && f != i) {
          e = blockEnd(i); block = ""
          for (j = i; j <= e; j++) { block = block line[j] "\n"; del[j] = 1 }
          ins[f - 1] = ins[f - 1] block
        }
      }
    }
  }
  if (rc) exit rc
  for (i = 0; i <= n; i++) {
    if (i > 0 && !del[i]) print line[i]
    if (i in ins) printf "%s", ins[i]
  }
  if (REPORT != "") print report > REPORT
}' >"$tmp/pass1" || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  # One blank line at most between blocks, none at the end.
  awk '/^[ \t]*$/ { blank = 1; next } { if (blank && seen) print ""; blank = 0; seen = 1; print }' "$tmp/pass1"
}

# change <subject>: apply TODO_OP on the latest list and push, again on the
# newer list each time another session pushed first.
change() {
  local subject=$1 try rc prev
  mktmp
  export TODO_NOW TODO_CUTOFF TODO_SEED TODO_SESSION_TAG TODO_REPORT="$tmp/report"
  TODO_NOW=$(now); TODO_CUTOFF=$(cutoff); TODO_SESSION_TAG=$(session_tag)
  sync_tip
  for try in 1 2 3 4 5 6 7 8 9 10; do
    TODO_SEED=$((RANDOM * 32768 + RANDOM))
    load_list >"$tmp/old"
    : >"$tmp/report"
    rc=0
    transform <"$tmp/old" >"$tmp/new" || rc=$?
    [ "$rc" -eq 0 ] || exit "$rc"
    if [ -n "$TIP" ] && cmp -s "$tmp/old" "$tmp/new"; then
      cat "$tmp/report"; return 0
    fi
    if commit_list "$tmp/new" "$subject"; then
      cat "$tmp/report"; return 0
    fi
    prev=$TIP
    sync_tip
    [ "$TIP" != "$prev" ] || die 2 "the push to the todo branch was refused: $(cat "$tmp/push.err")"
    sleep "0.$((RANDOM % 8 + 1))" 2>/dev/null || sleep 1
  done
  die 2 "the todo branch keeps changing: try again"
}

need() { [ "$1" -ge "$2" ] || usage; }

case "$cmd" in
  read)
    TODO_STALE_OK=1 sync_tip
    load_list
    echo "base: ${TIP:-none}" >&2
    if [ -n "$TIP" ]; then echo "writers: $(g log --format='%an <%ae>' "$TIP" | sort -u | paste -sd, - | sed 's/,/, /g')" >&2; fi
    ;;
  add)
    TODO_FOR=""; TODO_OPTS=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --for) need $# 2; TODO_FOR=$2; shift 2 ;;
        --opts) need $# 2; TODO_OPTS=$2; shift 2 ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    need $# 1
    export TODO_OP=add TODO_FOR TODO_OPTS TODO_TEXT
    TODO_TEXT=$(one_line "$*")
    change "todo: add"
    ;;
  claim)
    need $# 1
    [ -n "$(session_tag)" ] || die 64 "no session id: set TODO_SESSION to this session's tag"
    export TODO_OP=claim TODO_ID=$1
    change "todo: claim $1"
    ;;
  agent)
    need $# 3
    [ -n "$(session_tag)" ] || die 64 "no session id: set TODO_SESSION to this session's tag"
    export TODO_OP=agent TODO_ID=$1 TODO_AGENT=$2 TODO_BRANCH=$3
    change "todo: $1 to agent $2"
    ;;
  done|ask|note)
    need $# 2
    export TODO_OP=$cmd TODO_ID=$1 TODO_TEXT
    shift; TODO_TEXT=$(one_line "$*")
    change "todo: $cmd $TODO_ID"
    ;;
  release)
    need $# 1
    export TODO_OP=release TODO_ID=$1 TODO_TEXT
    shift; TODO_TEXT=$(one_line "$*")
    change "todo: release $TODO_ID"
    ;;
  merged|first|drop)
    need $# 1
    export TODO_OP=$cmd TODO_ID=$1
    change "todo: $cmd $1"
    ;;
  write)
    [ $# -eq 3 ] && [ "$1" = "--base" ] || usage
    [ -f "$3" ] || die 64 "no such file: $3"
    mktmp
    export TODO_OP=none TODO_NOW TODO_CUTOFF TODO_SEED=$((RANDOM * 32768 + RANDOM)) TODO_SESSION_TAG="" TODO_REPORT=""
    TODO_NOW=$(now); TODO_CUTOFF=$(cutoff)
    sync_tip
    [ "${TIP:-none}" = "$2" ] || die 5 "the list changed since it was read (now ${TIP:-none}): read it again"
    transform <"$3" >"$tmp/new"
    commit_list "$tmp/new" "todo: rewrite" || die 5 "the list changed while writing: read it again"
    echo "written: $TIP"
    ;;
  default)
    default_branch || die 2 "cannot tell the default branch"
    ;;
  session)
    session_tag; echo
    ;;
  hook)
    # Never fails and never blocks a session start.
    {
      cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
      repo=.
      g rev-parse --git-dir >/dev/null 2>&1 || exit 0
      list=$(sync_tip 2>/dev/null && load_list 2>/dev/null) || exit 0
      pending=$(printf '%s\n' "$list" | grep -c '^- \[ \] ' || true)
      blocked=$(printf '%s\n' "$list" | grep -c '^- \[?\] ' || true)
      running=$(printf '%s\n' "$list" | grep -c '^- \[[>~]\] ' || true)
      [ $((pending + blocked + running)) -gt 0 ] || exit 0
      name=$(basename "$(g rev-parse --show-toplevel 2>/dev/null || pwd)")
      echo "To-do list of $name (branch todo): $pending pending, $running in progress, $blocked blocked on a question. The user can type /todo to see it. This is information: start nothing from the list unless the user asks."
    } || exit 0
    ;;
  -h|--help|help) usage 0 ;;
  *) usage ;;
esac

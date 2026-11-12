#!/usr/bin/env bash
# todo.sh — the to-do queue as a local file, for sessions that cannot use the
# Todo Queue artifact (no claude.ai login, artifacts turned off, headless runs).
#
# The list is one markdown file inside the repository's git directory
# (<git-dir>/todo.md): never committed, never pushed, shared by every worktree
# of the clone, private to this machine. Changes are made under a lock, so two
# sessions never lose a line and never both take the same task.
#
# Usage: todo.sh [-C <repo>] <command> [args]
#
#   stamp                        print "<UTC time> <epoch ms> <session tag>"
#   read                         print the list (stderr: its base, for write)
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
#   write --base <base> <file>   replace the whole list (see read)
#   default                      print the default branch
#   path                         print where the list is kept
#
# <id> is the line's id, or a fragment of text found in exactly one line.
# Exit codes: 0 ok, 2 cannot read or write the list, 3 the task is taken,
# 4 no such line, 5 the list changed since it was read, 64 usage.
#
# Environment: TODO_FILE (another path for the list), TODO_SESSION (session
# tag, else taken from CLAUDE_CODE_SESSION_ID).

set -euo pipefail
export LC_ALL=C

repo=.
while [ $# -gt 0 ]; do
  case "$1" in
    -C) [ $# -ge 2 ] || { echo "todo.sh: -C needs a path" >&2; exit 64; }; repo=$2; shift 2 ;;
    *) break ;;
  esac
done
cmd=${1:-read}
[ $# -gt 0 ] && shift

LIST=""
tmp=""
locked=""
trap '[ -z "$tmp" ] || rm -rf "$tmp"; [ -z "$locked" ] || rmdir "$LIST.lock" 2>/dev/null || true' EXIT

die() { local code=$1; shift; echo "todo.sh: $*" >&2; exit "$code"; }
usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-64}"; }
g() { git -C "$repo" "$@"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
cutoff() { date -u -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -u -v-7d +%Y-%m-%d; }
one_line() { printf '%s' "$*" | tr '\n\r\t' '   '; }
base_of() { if [ -f "$LIST" ]; then cksum <"$LIST" | tr -s ' \t' '-' ; else echo none; fi; }

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
  if g remote get-url origin >/dev/null 2>&1; then
    b=$(GIT_TERMINAL_PROMPT=0 g ls-remote --symref origin HEAD 2>/dev/null | awk '$1 == "ref:" { sub("refs/heads/", "", $2); print $2; exit }') || b=""
    if [ -n "$b" ]; then printf '%s\n' "$b"; return 0; fi
    for b in main master; do
      if g rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null 2>&1; then printf '%s\n' "$b"; return 0; fi
    done
  fi
  g symbolic-ref -q --short HEAD 2>/dev/null
}

# The list lives in the git directory shared by every worktree of the clone.
locate() {
  local gd
  [ -z "$LIST" ] || return 0
  if [ -n "${TODO_FILE:-}" ]; then LIST=$TODO_FILE; return 0; fi
  gd=$(g rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || gd=""
  if [ -z "$gd" ]; then
    gd=$(g rev-parse --git-common-dir 2>/dev/null) || die 2 "not a git repository: $repo"
    case "$gd" in /*) ;; *) gd="$(cd "$repo" && cd "$gd" && pwd)" ;; esac
  fi
  LIST="$gd/todo.md"
}

load_list() { if [ -f "$LIST" ]; then cat "$LIST"; else printf '# To do\n'; fi; }

# One writer at a time. A lock left by a killed process is taken over after a minute.
lock() {
  local i=0
  mkdir -p "$(dirname "$LIST")" 2>/dev/null || die 2 "cannot write in $(dirname "$LIST")"
  while ! mkdir "$LIST.lock" 2>/dev/null; do
    i=$((i + 1))
    if [ -n "$(find "$LIST.lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then rmdir "$LIST.lock" 2>/dev/null || true; continue; fi
    [ -d "$LIST.lock" ] || [ "$i" -lt 3 ] || die 2 "cannot write in $(dirname "$LIST")"
    [ "$i" -lt 150 ] || die 2 "the list stays locked: $LIST.lock"
    sleep 0.1 2>/dev/null || sleep 1
  done
  locked=1
  tmp=$(mktemp -d "$LIST.tmp.XXXXXX") || die 2 "cannot write in $(dirname "$LIST")"
}

transform() {
  local rc=0
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

# change: apply TODO_OP to the list, under the lock.
change() {
  local rc=0
  locate; lock
  export TODO_NOW TODO_CUTOFF TODO_SEED TODO_SESSION_TAG TODO_REPORT="$tmp/report"
  TODO_NOW=$(now); TODO_CUTOFF=$(cutoff); TODO_SESSION_TAG=$(session_tag); TODO_SEED=$((RANDOM * 32768 + RANDOM))
  : >"$tmp/report"
  load_list | transform >"$tmp/new" || rc=$?
  [ "$rc" -eq 0 ] || exit "$rc"
  mv "$tmp/new" "$LIST"
  cat "$tmp/report"
}

need() { [ "$1" -ge "$2" ] || usage; }
need_session() { [ -n "$(session_tag)" ] || die 64 "no session id: set TODO_SESSION to this session's tag"; }

case "$cmd" in
  stamp)
    ms=$(date -u +%s)000
    echo "$(now) $ms $(session_tag)"
    ;;
  read)
    locate; load_list
    echo "base: $(base_of)" >&2
    ;;
  path)
    locate; echo "$LIST"
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
    change
    ;;
  claim)
    need $# 1; need_session
    export TODO_OP=claim TODO_ID=$1
    change
    ;;
  agent)
    need $# 3; need_session
    export TODO_OP=agent TODO_ID=$1 TODO_AGENT=$2 TODO_BRANCH=$3
    change
    ;;
  done|ask|note)
    need $# 2
    export TODO_OP=$cmd TODO_ID=$1 TODO_TEXT
    shift; TODO_TEXT=$(one_line "$*")
    change
    ;;
  release)
    need $# 1
    export TODO_OP=release TODO_ID=$1 TODO_TEXT
    shift; TODO_TEXT=$(one_line "$*")
    change
    ;;
  merged|first|drop)
    need $# 1
    export TODO_OP=$cmd TODO_ID=$1
    change
    ;;
  write)
    [ $# -eq 3 ] && [ "$1" = "--base" ] || usage
    [ -f "$3" ] || die 64 "no such file: $3"
    locate; lock
    [ "$(base_of)" = "$2" ] || die 5 "the list changed since it was read: read it again"
    export TODO_OP=none TODO_NOW TODO_CUTOFF TODO_SEED=$((RANDOM * 32768 + RANDOM)) TODO_SESSION_TAG="" TODO_REPORT=""
    TODO_NOW=$(now); TODO_CUTOFF=$(cutoff)
    transform <"$3" >"$tmp/new"
    mv "$tmp/new" "$LIST"
    echo "written"
    ;;
  default)
    default_branch || die 2 "cannot tell the default branch"
    ;;
  -h|--help|help) usage 0 ;;
  *) usage ;;
esac

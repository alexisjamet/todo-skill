#!/usr/bin/env bash
# Seeds the workspace: a git repository with an "origin" inside it, so the
# skill can push its todo branch without any network.
set -euo pipefail
export GIT_AUTHOR_NAME=eval GIT_AUTHOR_EMAIL=eval@example.com GIT_COMMITTER_NAME=eval GIT_COMMITTER_EMAIL=eval@example.com
git init -q -b main .
git init -q --bare .origin.git
echo ".origin.git" >> .git/info/exclude
mkdir -p src && echo "# shop" > README.md && echo "export const price = 10;" > src/pricing.js
git add -A && git commit -q -m "init"
git remote add origin "$PWD/.origin.git"
git push -q origin main
git remote set-head origin main
seed() { # seed <list file>: writes it as the todo branch of origin
  local blob tree commit
  blob=$(git hash-object -w "$1")
  tree=$(printf "040000 tree %s\t.claude\n" "$(printf "100644 blob %s\ttodo.md\n" "$blob" | git mktree)" | git mktree)
  commit=$(git commit-tree "$tree" -m "todo: seed [skip ci]")
  git push -q origin "$commit:refs/heads/todo"
  rm -f "$1"
}
cat > list.md <<'LIST'
# To do

- [>] `h2x` Signup: validate the VAT number field (added 2026-11-12T09:40:21Z) (session 7be04a95)
- [ ] `s3b` Search: results stay on the old query after pressing Back (added 2026-11-12T10:02:40Z)
- [?] `n5k` Pricing page: new plan names (added 2026-11-12T11:05:33Z) — question: keep "Pro" or rename it "Team"?
LIST
seed list.md

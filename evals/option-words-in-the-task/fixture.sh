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

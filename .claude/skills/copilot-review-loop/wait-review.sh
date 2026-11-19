#!/bin/sh
# Waits until Copilot itself has reviewed a pull request's head commit (or the commit given), then exits. Your own
# thread replies are recorded as reviews too, so it matches Copilot's account, not any review. Run it in the background.
# Usage: wait-review.sh <pr number> [<commit sha>]
set -e
pr=$1
[ -n "$pr" ] || { echo "usage: wait-review.sh <pr number> [<commit sha>]" >&2; exit 2; }
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
sha=${2:-$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq .headRefOid)}
copilot='copilot-pull-request-reviewer[bot]'
until gh api --paginate "repos/$repo/pulls/$pr/reviews" --jq ".[] | select(.user.login == \"$copilot\") | .commit_id" 2>/dev/null \
    | grep -q "^$sha"; do
    sleep 60
done

echo "Copilot reviewed #$pr at $sha"

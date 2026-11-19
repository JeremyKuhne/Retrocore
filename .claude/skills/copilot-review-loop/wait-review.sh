#!/bin/sh
# Waits until Copilot itself has reviewed a pull request's head commit (or the commit given), then exits. Your own
# thread replies are recorded as reviews too, so it matches Copilot's account, not any review. Run it in the background.
# A failed request is retried, but ten failures in a row stop it with an error rather than waiting for ever. It checks
# every WAIT_REVIEW_SECONDS (60 by default).
# Usage: wait-review.sh <pr number> [<commit sha>]
set -e
pr=$1
[ -n "$pr" ] || { echo "usage: wait-review.sh <pr number> [<commit sha>]" >&2; exit 2; }
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
sha=${2:-$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq .headRefOid)}
copilot='copilot-pull-request-reviewer[bot]'
failures=0
while :; do
    if commits=$(gh api --paginate "repos/$repo/pulls/$pr/reviews" --jq ".[] | select(.user.login == \"$copilot\") | .commit_id"); then
        failures=0
        if printf '%s\n' "$commits" | grep -q "^$sha"; then break; fi
    else
        failures=$((failures + 1))
        [ "$failures" -lt 10 ] || { echo "wait-review.sh: ten failed requests in a row for #$pr" >&2; exit 1; }
    fi

    sleep "${WAIT_REVIEW_SECONDS:-60}"
done

echo "Copilot reviewed #$pr at $sha"

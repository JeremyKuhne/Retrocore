#!/bin/sh
# Shows everything a pull request's review is waiting on, so nothing is missed:
#   - the head commit and whether Copilot has reviewed it;
#   - the body of Copilot's newest review, whose "Needs a closer look" banner can name bugs it never posts;
#   - every unresolved thread, marked UNANSWERED when it has no reply from you;
#   - the CI checks.
# Usage: review-state.sh <pr number>
set -e
pr=$1
[ -n "$pr" ] || { echo "usage: review-state.sh <pr number>" >&2; exit 2; }
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
owner=${repo%/*}
name=${repo#*/}
me=$(gh api user --jq .login)
copilot='copilot-pull-request-reviewer[bot]'

head=$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq .headRefOid)
echo "== #$pr head ${head%"${head#???????}"}"

# Reviews: --paginate, as the API returns 30 a page. Your own thread replies are reviews too, so filter by author.
latest=$(gh api --paginate "repos/$repo/pulls/$pr/reviews" \
    --jq ".[] | select(.user.login == \"$copilot\") | \"\(.commit_id) \(.submitted_at) \(.id)\"" | tail -1)
if [ -z "$latest" ]; then
    echo "Copilot: no review yet"
else
    set -- $latest
    if [ "$1" = "$head" ]; then echo "Copilot: reviewed the head at $2"; else echo "Copilot: last reviewed ${1%"${1#???????}"} at $2, NOT the head"; fi
    echo "-- newest Copilot review body:"
    gh api "repos/$repo/pulls/$pr/reviews/$3" --jq .body | sed 's/<[^>]*>//g' | grep -v '^[[:space:]]*$' || true
fi

echo "-- unresolved threads:"
query='query($owner: String!, $name: String!, $number: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $number) {
  reviewThreads(first: 100) { nodes { isResolved comments(first: 100) { nodes { databaseId author { login } path line body } } } } } } }'
gh api graphql -f query="$query" -F owner="$owner" -F name="$name" -F number="$pr" --jq "
    .data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) |
    (.comments.nodes[0]) as \$first |
    ([.comments.nodes[1:][] | select(.author.login == \"$me\")] | length) as \$replies |
    \"\(if \$replies == 0 then \"UNANSWERED\" else \"answered\" end) \(\$first.databaseId) \(\$first.path):\(\$first.line)\n  \(\$first.body | gsub(\"\n\"; \" \") | .[0:400])\""

echo "-- checks:"
gh pr checks "$pr" --repo "$repo" || true

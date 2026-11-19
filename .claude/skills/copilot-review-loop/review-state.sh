#!/bin/sh
# Shows everything a pull request's review is waiting on, so nothing is missed:
#   - the head commit and whether Copilot has reviewed it;
#   - the body of Copilot's newest review, whose "Needs a closer look" banner can name bugs it never posts;
#   - every unresolved thread in full, each comment with its author, marked UNANSWERED unless its latest comment is
#     yours (a reviewer's follow-up after your reply makes it unanswered again);
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

# Threads: every page of them (resolved threads count against the 100 a page), and each unresolved one's whole
# conversation, up to 100 comments, said so when there are more.
echo "-- unresolved threads:"
query='query($owner: String!, $name: String!, $number: Int!, $endCursor: String) { repository(owner: $owner, name: $name) {
  pullRequest(number: $number) { reviewThreads(first: 100, after: $endCursor) { pageInfo { hasNextPage endCursor }
    nodes { isResolved path line comments(first: 100) { totalCount nodes { databaseId author { login } body } } } } } } }'
gh api graphql --paginate -f query="$query" -F owner="$owner" -F name="$name" -F number="$pr" --jq "
    .data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) |
    \"\(if .comments.nodes[-1].author.login == \"$me\" then \"answered\" else \"UNANSWERED\" end) \(.comments.nodes[0].databaseId) \(.path):\(.line)\" +
    ([.comments.nodes[] | \"\n  [\(.author.login)]\n\(.body | split(\"\n\") | map(\"    \" + .) | join(\"\n\"))\"] | join(\"\")) +
    (if .comments.totalCount > (.comments.nodes | length) then \"\n  (\(.comments.totalCount - (.comments.nodes | length)) more comments; open the thread)\" else \"\" end)"

echo "-- checks:"
gh pr checks "$pr" --repo "$repo" || true

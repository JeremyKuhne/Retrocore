#!/bin/sh
# Resolves a pull request's open review threads that already carry a reply from you, and only those. Every open
# thread with no reply is listed and left open: a thread that arrived after you last looked is never closed unread.
# Usage: resolve-answered.sh <pr number> [<pr number> ...]
set -e
[ $# -gt 0 ] || { echo "usage: resolve-answered.sh <pr number> ..." >&2; exit 2; }
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
owner=${repo%/*}
name=${repo#*/}
me=$(gh api user --jq .login)
query='query($owner: String!, $name: String!, $number: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $number) {
  reviewThreads(first: 100) { nodes { id isResolved comments(first: 100) { nodes { databaseId author { login } } } } } } } }'
for pr in "$@"; do
    gh api graphql -f query="$query" -F owner="$owner" -F name="$name" -F number="$pr" --jq "
        .data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) |
        \"\(.id) \(.comments.nodes[0].databaseId) \([.comments.nodes[1:][] | select(.author.login == \"$me\")] | length)\"" |
    while read -r thread first replies; do
        if [ "$replies" -eq 0 ]; then
            echo "#$pr UNANSWERED, left open: $first"
            continue
        fi

        gh api graphql -f query='mutation($id: ID!) { resolveReviewThread(input: { threadId: $id }) { thread { isResolved } } }' \
            -f id="$thread" --jq '.data.resolveReviewThread.thread.isResolved' >/dev/null && echo "#$pr resolved $first" \
            || echo "#$pr FAILED to resolve $first"
    done
done

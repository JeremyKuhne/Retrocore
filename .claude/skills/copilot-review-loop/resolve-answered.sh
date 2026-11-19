#!/bin/sh
# Resolves a pull request's open review threads whose latest comment is yours, and only those. A thread with no reply
# from you, or with a reviewer's follow-up after your reply, is listed and left open, so nothing is closed unread.
# Every page of threads is checked, and a failed request stops the script with an error, so a run that read nothing
# never looks like one that found nothing to do.
# Usage: resolve-answered.sh <pr number> [<pr number> ...]
set -e
[ $# -gt 0 ] || { echo "usage: resolve-answered.sh <pr number> ..." >&2; exit 2; }
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
owner=${repo%/*}
name=${repo#*/}
me=$(gh api user --jq .login)
query='query($owner: String!, $name: String!, $number: Int!, $endCursor: String) { repository(owner: $owner, name: $name) {
  pullRequest(number: $number) { reviewThreads(first: 100, after: $endCursor) { pageInfo { hasNextPage endCursor }
    nodes { id isResolved first: comments(first: 1) { nodes { databaseId } } last: comments(last: 1) { nodes { author { login } } } } } } } }'
failed=0
for pr in "$@"; do
    # The query is its own assignment, so set -e stops on its failure, a later page's included, before any thread is
    # listed or resolved.
    threads=$(gh api graphql --paginate -f query="$query" -F owner="$owner" -F name="$name" -F number="$pr" --jq "
        .data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) |
        \"\(.id) \(.first.nodes[0].databaseId) \(.last.nodes[0].author.login == \"$me\")\"")
    [ -n "$threads" ] || { echo "#$pr no open threads"; continue; }

    # The loop reads a here-document, not a pipe, so it runs in this shell and its failures count.
    while read -r thread first answered; do
        if [ "$answered" != "true" ]; then
            echo "#$pr UNANSWERED, left open: $first"
            continue
        fi

        if gh api graphql -f query='mutation($id: ID!) { resolveReviewThread(input: { threadId: $id }) { thread { isResolved } } }' \
            -f id="$thread" --jq '.data.resolveReviewThread.thread.isResolved' >/dev/null; then
            echo "#$pr resolved $first"
        else
            echo "#$pr FAILED to resolve $first" >&2
            failed=1
        fi
    done <<EOF
$threads
EOF
done

exit $failed

---
name: steward
description: Look after a Retrocore pull request when GitHub activity arrives (Copilot reviews, review comments, CI results) or when asked to watch, babysit, fix up or get a PR clean or green. Points to the repository's own procedures, which take precedence over generic pull-request guidance.
license: MIT
compatibility: Requires access to the repository's pull requests, through the GitHub CLI or the session's GitHub API tools.
metadata:
   portability: repository
   applicability: retrocore
   risk: remote-write
   maturity: canary
   requires: none
   related: copilot-review-loop, pre-pr-self-review, retrocore-conformance, retrocore-media-lifecycle
---

# Steward a pull request

Retrocore's pull-request procedure is [copilot-review-loop](../copilot-review-loop/SKILL.md). Read it now and follow
its [Run the loop](../copilot-review-loop/SKILL.md#run-the-loop) section for every review or CI event on the PR; where
it and generic pull-request guidance differ, it wins. Without the GitHub CLI, use its
[Without the GitHub CLI](../copilot-review-loop/SKILL.md#without-the-github-cli) section rather than skipping the
steps its scripts do.

Before acting on an event, check the loop's two gates, which are the steps most often skipped:

- **Before the first Copilot review:** [pre-pr-self-review](../pre-pr-self-review/SKILL.md) is done, and the whole diff
  has been reviewed independently, by a reviewer given the diff but not your conclusions. If not, do both before
  requesting Copilot.
- **After three Copilot rounds, or once fixes start breaking other things:** stop fixing finding by finding and run
  the independent full review again.

If a skill named here is not in your checkout (a branch older than it), fetch the default branch and read it from
there: `git fetch origin main`, then `git show origin/main:.claude/skills/<name>/SKILL.md`.

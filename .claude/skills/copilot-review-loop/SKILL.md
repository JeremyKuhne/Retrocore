---
name: copilot-review-loop
description: Shape a change into reviewable pull requests and take each through Copilot's review in few rounds, reading every thread and review summary, replying, resolving only answered threads, and waiting for Copilot's own review of the head. Use when opening a PR or a stack of them, addressing review comments, iterating on Copilot's review, getting a PR green or clean, or checking a PR's review state.
license: MIT
compatibility: The scripts require the GitHub CLI (gh) authenticated for the repository, and a POSIX shell (Git Bash on Windows); without them, use the session's GitHub API tools (see Without the GitHub CLI).
metadata:
   portability: repository
   applicability: retrocore
   risk: remote-write
   maturity: canary
   requires: none
   related: pre-pr-self-review, retrocore-conformance, retrocore-media-lifecycle
---

# Copilot review loop

This skill covers what happens around a pull request: its size and stacking, and the review loop itself. The checks
before the first reviewable version are `pre-pr-self-review`, with `retrocore-conformance` and
`retrocore-media-lifecycle` for their domains; do them first. Copilot reports a few findings per pass, so an unreviewed
or oversized diff becomes many rounds, and each fix that breaks something else adds more. On the BBC Micro series
(#74-#82, November 2026) #76 alone took 27 review-fix commits over 22 Copilot reviews; one independent full review
then found seven real bugs that fifteen Copilot rounds had not.

## Shape the pull requests

- **Size.** Aim at about 3,000 changed lines. Split annotated ROM sources by area (VDU, tape, OSBYTE and so on); every
  `;;` contract in a 14,000-line PR is reviewed a few at a time.
- **Shared code in its own PR.** A change to shared media, chips or the debug host reaches every machine that uses it.
  Review it on its own, with its sibling variants (`pre-pr-self-review`), before the machine PR that needs it.
- **Stacks at most two deep.** Open the next PR when the one below is merged or nearly clean, and request Copilot only
  on the bottom one; every fix low in a deep stack is merged up and re-reviewed in every PR above it.
- **An independent review before Copilot's.** Beyond the self-review checklist, have a fresh reviewer read the whole
  diff without your conclusions: a subagent given the diff, or `/code-review high`. Fix what it confirms, then
  request Copilot.

## Run the loop

Scripts beside this file take PR numbers and work in the current repository.

- `review-state.sh <pr>`: the head commit, whether Copilot has reviewed it, the body of its newest review, every
  unresolved thread with its whole conversation (UNANSWERED unless its latest comment is yours, so a reviewer's
  follow-up reopens the question), every page of threads, and the checks.
- `resolve-answered.sh <pr>...`: resolves only threads whose latest comment is yours, and lists the rest.
- `wait-review.sh <pr> [sha]`: run in the background after re-requesting; exits when Copilot's own account reviews
  that commit. Your replies are recorded as reviews too, so never wait on "any new review".

Without the GitHub CLI (a cloud session, for example), do what each script does through the GitHub API tools
rather than skipping it; see [Without the GitHub CLI](#without-the-github-cli).

Each round:

1. Run `review-state.sh`. Read every thread **and the newest review's body**: a "Needs a closer look" banner can name
   bugs that are never posted as threads, and those are findings like any other. A banner that names no bug, only
   checks Copilot could not run, is answered by running them and reporting what ran (`pre-pr-self-review`'s evidence
   rules apply: skipped is not passed).
2. Verify each finding in the code before changing anything. For a stacked PR, answer a finding about what a later PR
   does by pointing to it; decline feature creep. Both are replies, then resolved.
3. Fix the class, not the instance, with the checks in `pre-pr-self-review` and `retrocore-conformance`: siblings of
   the pattern, every caller and format a shared change reaches, files other tools read (MAME rejects a DMK whose
   reserved header bytes are not zero), and a regression test shown to fail without its fix.
4. Fix everything from the round, run the full suite, and push once.
5. Reply to every thread with what changed and the commit, then run `resolve-answered.sh`.
6. Re-request with `gh pr edit <n> --add-reviewer "@copilot"`, then `wait-review.sh <n>` in the background.

**Clean** means Copilot reviewed the head commit and reports no open issues, no thread is unresolved, its banner names
no unexamined bug, and the checks pass. A resolved thread is not proof of a fix; the commit and its test are.

**Stop and re-review** when a PR passes three rounds or fixes start breaking other things: run the independent full
review again rather than patching finding by finding.

## Without the GitHub CLI

The scripts need `gh`. Where it is not available, do the same steps with the GitHub API tools the session has:

- **Yours** means written by the account the session is authenticated as (for example, the login a "who am I"
  call returns).
- **Copilot** is `copilot-pull-request-reviewer[bot]` in the REST API and `copilot-pull-request-reviewer` in GraphQL
  and some tools; accept either.
- **`review-state.sh`:** read the PR's head commit; list every page of its reviews and find Copilot's newest, noting
  whether its commit is the head; read that review's body; list every page of unresolved review threads, each with
  its comments (the script reads a thread's first 100 and reports when there are more: then page the thread's
  comments, or open it, before judging it), and treat a thread as unanswered unless its latest comment is yours;
  list the head's check runs.
- **`resolve-answered.sh`:** resolve an unresolved thread only if its latest comment is yours, by the thread's node ID.
- **Re-requesting:** request a Copilot review on the PR.
- **`wait-review.sh`:** wait for a review whose author is Copilot and whose commit is the head you pushed. Where the
  session is woken by pull-request events, wait for that event rather than polling. Your own replies arrive as
  reviews and comments too, so they never count.

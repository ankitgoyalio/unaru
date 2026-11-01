# Issue tracker: GitHub

Issues and specs live in GitHub Issues for `ankitgoyalio/unaru`.
Use the `gh` CLI from this repository.

## Read and publish tickets

- Read an issue with `gh issue view <number> --json number,title,body,labels,comments`.
- List issues with `gh issue list --state open --json number,title,body,labels`.
- Create an issue with `gh issue create --title "..." --body-file <path>`.
- Add a comment with `gh issue comment <number> --body-file <path>`.
- Apply a label with `gh issue edit <number> --add-label "..."`.
- Remove a label with `gh issue edit <number> --remove-label "..."`.
- To close an issue, post the explanation first, then run `gh issue close <number>`.

Write multiline bodies to a temporary file and pass its path with `--body-file`.

When a skill says "publish to the issue tracker", create a GitHub issue.
When a skill says "fetch the relevant ticket", read the GitHub issue.

Before the first issue creation in a session, verify the target with
`gh repo view --json nameWithOwner`. The target is `ankitgoyalio/unaru`.
If the target differs, resolve the mismatch before creating the issue.

## Parent issues and blockers

Use GitHub's native sub-issues to connect child tickets to a parent.
Use native issue dependencies to record blockers.

To add a child issue, run:
`gh api --method POST repos/ankitgoyalio/unaru/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>`

To add a blocker, run:
`gh api --method POST repos/ankitgoyalio/unaru/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`

Get an issue's database ID with:
`gh api repos/ankitgoyalio/unaru/issues/<number> --jq .id`

If native links are unavailable, put `Part of #<parent>` and
`Blocked by: #<number>` at the top of the child issue body.
An issue is unblocked when every blocker is closed.

## Pull requests as a triage surface

**PRs as a request surface: no.**

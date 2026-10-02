# GitHub releases

After this workflow is merged, each PR merged into `ClaweOfTheWild/Wild` `main`
publishes one GitHub release. Closing an unmerged PR does nothing. There is no
historical backfill, manual dispatch, addon packaging, or `Wild.toc` update.

## Version and notes

Before merging, use zero or one of these labels:

| Label | Color | Bump from `0.0.10` |
| --- | --- | --- |
| `release:major` | Purple (`8957E5`) | `1.0.0` |
| `release:minor` | Blue (`0075CA`) | `0.1.0` |
| `release:patch` | Green (`2DA44E`) | `0.0.11` |
| No bump label | Not applicable | `0.0.11` |

Multiple bump labels fail explicitly. Other labels do not change the default
patch bump. Major and minor reset lower components; there is no pre-1.0 downgrade.

The baseline is the highest existing canonical `X.Y.Z` tag, compared numerically
across every API page. It is not the latest release, tag creation date, or TOC
version. Tags with a `v` prefix, prerelease/build suffix, or leading zero are
ignored. No valid tags is an error, not permission to start over at zero.

The release title and tag are exactly `X.Y.Z`, without `v`. The body is the
merge-event PR title, two newline characters, and the complete PR description.
An absent or empty description produces only the title. Quotes, Unicode,
whitespace, Markdown, and shell syntax remain data. Reruns use the original
event's labels and text, not later PR edits.

The tag points to `pull_request.merge_commit_sha`: the merge commit for a normal
merge, or the squash commit for a squash merge. It never follows the current
`main` tip or the contributor's head SHA.

## Trust and permissions

`pull_request_target` on `closed` supports merged fork PRs. The job also checks
the owning repository, target repository, `main`, and the merged flag.
Checkout uses the event's trusted base SHA (`github.sha`), never PR head code or
the test merge ref. PR text is read from event JSON, serialized as UTF-8 JSON,
and never interpolated into executable code.

Only the publishing job has `contents: write`. Its token is passed only to the
publishing step; checkout does not persist credentials. Tests use `pull_request`
with `contents: read`, no publishing token, and a fake HTTP API.

This is a scoped exception to the MSX GitHub App-token default: this single-repo
publisher uses the built-in `GITHUB_TOKEN`, needs no App secrets or PAT, and does
not need downstream release/tag workflows. Events created with that token do
not start ordinary downstream Actions workflows. Revisit an installation token
if that requirement changes. Repository rules must allow Actions to create
numeric tags and releases; the workflow never bypasses rules or changes access.

## Queue and recovery

All release runs share `wild-github-release` with `queue: max` and
`cancel-in-progress: false`. GitHub retains up to 100 pending runs instead of
replacing the pending run on each merge. Processing order follows entry into the
queue, not necessarily merge time. Versions follow processing order, while
every version still targets its own PR's commit.

GitHub cancels arrivals beyond that queue limit. Monitor failed/canceled runs
and use **Re-run all jobs** on the original run after the backlog drains.
There is no scheduled recovery or silent historical sweep. A failed run does
not stop later queued PRs from publishing.

The publisher first reserves a numeric annotated tag whose message records the
PR number and commit, then creates the release. Ref creation is atomic; a
competing writer causes an explicit failure instead of replacing a tag.

For network, rate-limit, permission, or service failures, resolve the cause and
rerun the original run. A reserved tag is reused, including after a lost API
response or after later PRs release. An already matching release is a no-op.
An older retry uses GitHub's `legacy` latest-selection behavior rather than
forcing itself to become the latest release.

Do not move or delete reservation tags. A foreign tag, mismatched release
content, or ambiguous ownership fails without changing existing data.
Investigate these conflicts before retrying. Conflicting labels captured at
merge also require maintainer intervention: editing labels later does not
rewrite the original event. Never bypass an ownership error by deleting tags.

## Developer checks

PowerShell 7.4+, Python, and Go are needed only for development, not the addon.
Install the test tools, then run the same check command as CI:

```powershell
Install-PSResource -Name Pester -Version '[6.1.0,7.0.0)' -TrustRepository
Install-PSResource -Name PSScriptAnalyzer -Version '[1.25.0,2.0.0)' -TrustRepository
python -m pip install -r .github/requirements-release-tests.txt
./.github/scripts/Test-Release.ps1
```

The tests mock every publishing HTTP request. They do not create live tags or
releases. Checks include Pester, parsed workflow contracts, PSScriptAnalyzer,
yamllint, actionlint, and offline zizmor.

Two narrow linter exceptions are intentional: zizmor's generic warning for the
trusted metadata-only trigger, and actionlint 1.7.12's unrecognized `queue` key
in `release.yml`. The Python workflow test validates that entire concurrency
mapping exactly; all other actionlint checks remain enabled.

External actions use verified commit pins. Dependabot proposes weekly updates
with a deliberate seven-day cooldown.

## References

- [GitHub concurrency and its queue limit](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)
- [Pull request merge SHA semantics](https://docs.github.com/en/rest/pulls/pulls#get-a-pull-request)
- [Token-triggered workflow behavior](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#triggering-a-workflow-from-a-workflow)
- [Scoped implementation and token exception](https://github.com/ClaweOfTheWild/Wild/issues/21)

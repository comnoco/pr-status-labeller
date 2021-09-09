# PR Status Labeller

This GitHub Action labels PRs based on their current status and updates those labels when various
lifecycle events occur. This allows the status of PRs to be easily viewed in project management
software such as Shortcut, as the labels are displayed next to the PRs in the linked tickets.

- New PRs are labelled by default with `awaiting review`
- Approved PRs are labelled as approved once a threshold of approvals is met (default:
  `code approved` after `1` approval)
- When changes are requested, the default `changes requested` label is applied
- When a PR is closed, the `closed` label is applied (can be disabled in the config)
- When a PR is merged, the `merged` label is applied (can be disabled in the config)
- When a PR moves between these statuses, any invalid labels are automatically removed

This Action works well with
[`crazy-max/ghaction-github-labeler`](https://github.com/crazy-max/ghaction-github-labeler), which
allows you to manage labels in a repository using a config file rather than having to manually add
them to the labels list, which makes managing labels across multiple related repositories much less
hassle!

We also recommend using
[`mschilde/auto-label-merge-conflicts`](https://github.com/mschilde/auto-label-merge-conflicts),
which checks PRs whenever the PR or `main` is updated and automatically labels PRs which have
conflicts, making them much easier to spot in the PR list.

This Action was adapted from
[`abinoda/label-when-approved-action`](https://github.com/abinoda/label-when-approved-action), so
shout out and thanks to [Abi Noda](https://github.com/abinoda) for creating the original action! :)

## Example usage

```yaml
name: 'PR Status Labeller'

on:
  pull_request:
  pull_request_review:

jobs:
  pr_status_labeller:
    runs-on: ubuntu-latest
    steps:
      - name: Run Labeller
        uses: comnoco/pr-status-labeller@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          AWAITING_REVIEW_LABEL: 'awaiting review' # default: 'awaiting review'
          CHANGES_REQUESTED_LABEL: 'changes requested' # default: 'changes requested'
          CLOSED_LABEL: 'closed' # default: 'closed'
          CODE_APPROVED_LABEL: 'code approved' # default: 'code approved'
          MERGED_LABEL: 'merged' # default: 'merged'
          APPLY_CLOSED_LABEL: true # default: true
          APPLY_MERGED_LABEL: true # default: true
```

# Claude PR agent

Every agent44bot repo can run the Claude PR agent. The logic lives in
`.github/workflows/claude-agent.yml` (reusable workflow in this repo); each
repo opts in with the thin caller `.github/workflows/claude.yml`.

## What it does

- **Auto-review**: every non-draft PR gets a review comment when opened or
  marked ready for review. Pushes to an open PR do not re-trigger it; comment
  `@claude review again` when you want a fresh pass.
- **`@claude` mentions**: mention `@claude` in an issue or PR comment, a
  review, or a new issue body and it answers or pushes the requested changes
  to the PR branch.
- **Issue to PR**: add the `claude` label to an issue and it implements the
  change on a `claude/issue-N` branch and opens a PR that closes the issue.

## Setup for a new repo

1. Install the Claude GitHub App: https://github.com/apps/claude
2. From an agent44_app checkout:

   ```sh
   CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat... bin/claude-agent-install agent44bot/<repo>
   ```

The token comes from `claude setup-token` and bills to the Claude
subscription. Only users with write access to the repo can trigger the agent.

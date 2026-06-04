# Claude PR agent

Every agent44bot repo can run the Claude PR agent. The logic lives in
`.github/workflows/claude-agent.yml` (reusable workflow in this repo); each
repo opts in with the thin caller `.github/workflows/claude.yml`.

## What it does

- **Auto-review**: every non-draft PR gets a review comment when opened or
  marked ready for review. Pushes to an open PR do not re-trigger it; any
  `@claude` mention (e.g. `@claude review again`) gets a fresh pass.
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

   The installer sets the `CLAUDE_CODE_OAUTH_TOKEN` secret on the repo and
   commits the caller workflow to its default branch.

The token comes from `claude setup-token` (a Claude Code CLI command) and
bills to the Claude subscription. Only users with write access to the repo
can trigger the agent.

## Troubleshooting

**401 Invalid bearer token** -- If the workflow logs show a 401 with "Invalid
bearer token", the `CLAUDE_CODE_OAUTH_TOKEN` secret is either truncated or
revoked. Regenerate it with `claude setup-token`, then update the secret on
the repo (Settings > Secrets and variables > Actions) and re-run the workflow.

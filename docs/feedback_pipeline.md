# Feedback pipeline

In-app feedback that turns into a reviewed PR, with Rich approving twice.

- **Phase 1 (live, PR #529):** the Feedback button, `Feedback` records with
  attachments, a push to Rich, a "got it" email to the sender, and
  `/admin/feedbacks`, where marking an item Live emails the sender.
- **The board (2026-09-22):** `/admin/feedbacks` is a board with the columns
  Pre-dev, Dev, Post-dev, Review PR, Deploy and Done. Rich can add, edit and
  delete items there. Everything lives in the app: the agent44bot@gmail.com
  inbox copy was dropped. Senders still get their three emails (got it, a
  question, it's live).
- **Phase 2 (this doc):** the Mac mini reads each item, proposes a plan,
  builds it after Rich approves, opens a PR, and merges only when Rich taps
  Merge it.

## The flow

```
received ──(mini: plan)──▶ planned ──① Work on it──▶ approved ──(mini: build, PR, CI green)──▶ pr_ready
    ▲                        │  │                        ▲                                       │  │
    │            Ask them ◀──┘  └──▶ Close               └──────── Request changes ◀───────────────┘  │
    │               │                                                                                ② Merge it
    │         needs_info                                                                               │
    └── sender answers                                                     shipped ◀──(mini: merged + deploy verified)
```

| Status | Who acts next | What happens |
|---|---|---|
| `received` | mini | Reads the message, attachments, and the code (read-only), and posts a plan. **Push: "Plan ready".** |
| `planned` | Rich | **① Work on it**, **Ask them** (question emailed to the sender, answered on their feedback page), or **Close** (optional note to the sender). |
| `needs_info` | sender | Their answer puts the item back to `received`, and the mini re-plans with it. **Push: "Answer from ...".** |
| `approved` / `changes_requested` | mini | Builds on a branch, opens or updates the PR, and waits for CI and the auto-review. Reports the PR and head SHA. **Push: "Ready to merge".** |
| `pr_ready` | Rich | Views the PR on GitHub, then **② Merge it** or **Request changes** (a note the mini acts on). |
| `merge_requested` | mini | Merges with `gh pr merge --squash --match-head-commit <sha>`, waits for the auto-deploy, and verifies prod (200 and `SolidQueue::Process.count > 0`). |
| `shipped` | nobody | The app emails the sender "it's live" with the note (drafted by the agent, editable by Rich at ②). |
| `closed` | nobody | Done without a change. |

If the mini fails at any step, it records `agent_error` and Rich gets
**Push: "Stuck: ..."**. The status does not move, so fixing the problem and
pressing **Retry** re-queues the item.

Rich can also ship an item by hand at any point (Mark Live with a note), for
the cases he fixes himself.

## Board columns

| Column | Statuses |
|---|---|
| Pre-dev | `received`, `planned`, `needs_info` |
| Dev | `approved` with no PR yet, `changes_requested` |
| Post-dev | `approved` with a PR whose checks aren't green yet |
| Review PR | `pr_ready` |
| Deploy | `merge_requested` |
| Done | `shipped`, `closed` |

Manual moves are limited to "back to Pre-dev" (a re-plan, which also
reopens a Done item), Mark Live, and Close. Review PR and Deploy are reached
only through the agent and Rich's Merge it.

## Guardrails

- **Feedback text is untrusted input.** The plan step runs with read-only
  tools. Nothing is built until Rich approves the plan (①). The agent never
  gets Fly or production credentials; the deploy check uses the same
  read-only commands the runbook uses.
- **Containment of each Claude Code run** (`FeedbackAgent::Worker#claude_settings`):
  - Read is blocked outside the worktree and attachments folder, and the
    mini's secret files are denied outright.
  - Edit/Write are allowed only inside the worktree (`Edit(//<worktree>/**)`).
  - Every Bash command, including test code the agent writes, runs in Claude
    Code's OS sandbox. It can write only in the worktree and tmp, cannot read
    the secret paths, and has **no network**. Only the Ruby toolchain folders
    are readable in the home folder.
  - The env files' secrets (`API_TOKEN`, Brevo keys, `ANTHROPIC_API_KEY`) are
    removed from the agent's environment.
  - A live probe on 2026-09-22 confirmed that reading `~/.agent44_smoke_env`,
    writing to the home folder, and reaching `example.com` were all blocked,
    while `bin/rails test` still passed.
- **Who can send feedback:** only users Rich switches on
  (`users.feedback_access`, the Feedback switch on `/admin/users`, off by
  default). A new sign-up can't put text in front of the agent.
- **Uploads are identified by their bytes** (`Feedback.acceptable_file?`):
  photos, PDF, .docx/.xlsx/.pptx and UTF-8 text only. An executable or HTML
  file renamed `.png` is refused, and old macro-capable .doc/.xls files
  aren't accepted.
- **Protected files:** the worker refuses to push any change touching
  `.github/`, `Gemfile*`, `Dockerfile`, `fly.toml`, `bin/`, credentials,
  `config/importmap.rb`, `vendor/`, JS lockfiles, or the agent's own code
  (`FeedbackAgent::Worker::PROTECTED_PATHS`). CI workflows in a PR run with
  repo secrets, and dependency and deploy files change what gets installed
  and shipped, so a person changes those by hand.
- **Security-sensitive PRs are flagged:** files touching sign-in, sessions,
  permissions, roles, impersonation or API tokens are reported, and the
  board and item page show a red "read the diff carefully" warning.
- **CI holds no production secrets:** tests use test-only encryption keys,
  and the workflow token is read-only (PR #541). PR code, including
  agent-built code, runs in CI before anyone merges it.
- **Merging is Rich's call (②).** The Merge it button sends the head SHA Rich
  was looking at. The app refuses it unless that SHA is still the PR's
  latest reported head and checks are green. The mini re-checks against
  GitHub and merges with `--match-head-commit`, so a push after Rich looked
  can never be merged by that tap. (This closes the #141 gotcha where a merge
  during check lag squashed an earlier commit.)
- **One worker, one item at a time.** Each item is claimed with
  `agent_claimed_at` so a restarted worker never double-builds.
- The usual house rules (PR-only, worktrees, no em dashes, the
  `nyk_changelog.yml` line) apply to agent-built PRs exactly as to hand-built
  ones.

## Pieces

**App (Rails, PR "Feedback phase 2: app side")**
- `feedbacks` gains `plan`, `thread` (JSON questions and answers), PR fields
  (`pr_number`, `pr_url`, `pr_head_sha`, `pr_checks`, `pr_summary`),
  `ship_note`, `merge_requested_sha`, `agent_error`, `agent_claimed_at`, and
  timestamps for each gate.
- `/admin/feedbacks/:id` shows one item with the gate buttons. Every push
  deep-links there.
- The sender's feedback page shows a plain status (Received, Question for
  you, In progress, Live, Closed) and an answer box when asked a question.
- The token API (`API_TOKEN`, like `apply_requests`):
  - `GET /api/v1/feedbacks/queue`: items waiting on the mini, with signed
    attachment URLs.
  - `POST /api/v1/feedbacks/:id/claim`
  - `POST /api/v1/feedbacks/:id/plan` with `plan`, optional `question`
  - `POST /api/v1/feedbacks/:id/pr` with `number`, `url`, `head_sha`,
    `checks`, `summary`, `ship_note`
  - `POST /api/v1/feedbacks/:id/shipped` with `sha`
  - `POST /api/v1/feedbacks/:id/error` with `message`

**Mini: `bin/feedback-agent`** (`lib/feedback_agent/`, launchd `ai.agent44.feedback-agent`)
- Polls the queue every minute, and goes straight to the next item after
  real work. One worker per machine (a lock file). Loads `API_TOKEN` from
  `~/.agent44_smoke_env` like the smoke scripts. Runs Claude Code on the
  mini's own login: `ANTHROPIC_API_KEY` is stripped so the app's API key
  isn't billed.
- **plan:** `claude -p` in a detached `origin/main` worktree with only
  Read/Grep/Glob, attachments downloaded and passed with `--add-dir`, and
  structured output `{plan, question}`.
- **build:** a worktree on `feedback/<id>` (new from `origin/main`, or the
  existing branch after Request changes or Retry). `claude -p` in
  acceptEdits mode, allowed only edits, `bin/rails test`, rubocop,
  brakeman and local git; `git push`, `gh`, `fly`, `curl` and the web are
  denied. The worker commits any leftovers, pushes, opens the PR, reports
  it as pending, waits for `test` and `claude / auto-review` to settle, and
  reports green (or stuck with the failing checks).
- **merge:** re-reads the PR from GitHub. It must be open, its head must be
  the SHA Rich approved, and no checks may be failing. Then
  `gh pr merge --squash --match-head-commit`, wait for the `fly-deploy.yml`
  run on the merge commit, verify prod (200 and SolidQueue processes), and
  report shipped.
- Any failure is reported as stuck with the reason, and **Retry** re-runs
  the step.

Install and run on the mini:
```sh
bin/feedback-agent install     # launchd agent; logs in ~/.feedback-agent/agent.log
bin/feedback-agent --once      # one pass by hand
bin/feedback-agent uninstall
```
Set `FEEDBACK_AGENT_MODEL` to change the model (default `claude-opus-5-5`).
A plan costs about $0.35; a build costs more, depending on size.

## Open items

- A preview link on the phone: `bin/preview` runs on the mini, so it is
  reachable only on home Wi-Fi until it is exposed (for example with
  Tailscale).
- Skipping ① for tiny copy changes, once the plans have earned trust.
- Telegram is muted app-wide; pushes are the channel.

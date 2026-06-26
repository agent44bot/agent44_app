# agent44_app — notes for agents

## NO direct commits to main — PR-only workflow

- **Never commit or push directly to `main`.** Every change goes on a new
  branch, pushed as a PR, reviewed by the Claude PR agent
  (`.github/workflows/claude.yml`), then merged. `main` is branch-protected
  (required check `claude / auto-review`, enforced for admins), so direct
  pushes are rejected.
- Work in a **git worktree** (`git worktree add ... -b <branch> origin/main`)
  — never switch branches in the shared working tree; other agents may have
  uncommitted work there.
- Flow: worktree → commit → push → `gh pr create` → wait for the auto-review
  run to pass → squash-merge → remove the worktree.
- This applies to all agent44bot repos, not just this one.
- Do not merge a PR yourself unless the owner explicitly says to; open it,
  wait for checks, and report.

## Local branch previews — test a PR before merge

- **`bin/preview` boots the current worktree's branch on `:3001`** (main stays
  on `:3000`), so the owner can A/B the branch against main before merging.
- By default it symlinks the worktree's `storage/development.sqlite3` to the
  **main tree's** real dev data, so `:3001` looks like `:3000` but with the
  branch's code. This sidesteps the gotcha that every worktree gets its own
  empty dev DB.
- **Schema-change branches**: don't share the DB (migrating it mutates the
  main `:3000` data). Use `OWN_DB=1 bin/preview` for an isolated seeded DB.
- When you open a PR worth eyeballing, boot it in the background and hand the
  owner the `http://localhost:3001` link.

## House rules (for any agent touching this code, incl. PR review)

- **`Current.user`, never `Current.session.user`.** The session user is the
  real admin even during impersonation ("View as"), so session.user leaks
  past it. Flag any new `Current.session.user` in review.
- **User activity = `PageView`, not `Session`.** `Session.updated_at` freezes
  at sign-in (persistent cookies), so it lies about activity.
- **Every new foreign key to `users` needs a matching `has_many` on `User`
  with `dependent: :destroy` or `:nullify`.** Otherwise the Apple-required
  delete-account flow breaks at runtime.
- **No em or en dashes (— –) in user-facing or AI-generated copy.** Use
  commas, colons, or parentheses.
- **`config/recurring.yml` schedules must parse to `Fugit::Cron`.** A phrase
  that parses to a point in time crash-loops prod at boot (SolidQueue runs
  inside puma). Guarded by test/lib/recurring_schedule_test.rb; "every week
  on X" is the known foot-gun.
- **Never call the Anthropic API (or any external API) in tests.** Mock it.
- **Workspace roles are owner/admin/editor/viewer.** Owner/admin =
  `Workspace#manager?` (always sees billing/pricing); use workspace roles for
  customer-tier gating, never new global User roles.
- **User-facing NY Kitchen changes get a line in `config/nyk_changelog.yml`**
  (plain language, dated; it feeds the Sunday owner report).
- **Post-deploy verification is two checks**: the site returns 200 AND
  `SolidQueue::Process.count > 0` in prod. A crash loop can serve a lucky
  200 while jobs are dead.
- **Mobile composer inputs**: 16px font minimum (iOS zoom), size chat boxes
  to `visualViewport`, no autofocus/refocus on touch.
- The NY Kitchen contact's name is spelled **Lora** (never "Laura").

## Deploys — READ BEFORE `fly deploy`

- **Serialize deploys: only ONE agent runs `fly deploy` at a time.** This app
  runs on a **single Fly machine**. Concurrent deploys fight over that machine's
  lease and leave prod **stopped** — the proxy logs `lease currently held by
  …@tokens.fly.io` / `rate limit exceeded` and requests return **HTTP 000**. If
  more than one agent might deploy, coordinate so they never overlap.
- **Recover a stuck machine** (HTTP 000/502 after a contended deploy):
  `fly machine start <id>` (get `<id>` from `fly status`), then confirm
  `https://agent44labs.com/` returns 200.
- **Do NOT `fly scale count >1`.** The database is **SQLite on a per-machine
  volume** (`DATABASE_URL=sqlite3:///data/production.sqlite3`, `[[mounts]] /data`).
  A second machine gets its own volume → split-brain data. Multi-machine /
  true zero-downtime deploys would require migrating to a shared DB
  (Fly Postgres or LiteFS) first — a separate project, not a one-liner.
- Default deploy path is `fly deploy` from `main`.

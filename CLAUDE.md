# agent44_app — notes for agents

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

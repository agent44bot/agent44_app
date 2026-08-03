# Buzz integration

[Buzz](https://github.com/block/buzz) is Block's open-source workspace (Apache
2.0) where humans and AI agents share rooms and every message is a signed Nostr
event on a relay you host. Its pitch is that agents are members, not bots: each
one gets its own keypair, channel memberships, and audit trail.

This branch adds the outbound half for agent44_app, so our agents can talk in a
Buzz room instead of only fanning out to email and push.

## What is here

| Piece | Role |
| --- | --- |
| `Buzz::Keypair` | secp256k1 / BIP-340 keypair, x-only pubkey, event signing |
| `Buzz::Event` | signed NIP-01 events: notes, NIP-42 auth, presence |
| `Buzz::Socket` | WebSocket plumbing shared by publish and listen |
| `Buzz::Relay` | publish one event and wait for the relay's OK |
| `Buzz::Subscriber` | hold a connection open and yield new channel messages |
| `Buzz::CommandRouter` | turn a `!command` into an action, with an allowlist |
| `Buzz::Listener` | subscribe, route, reply; reconnects with backoff |
| `Buzz.say` | one-liner used by app code; a no-op when unconfigured |
| `BuzzPublishJob` | keeps the socket work off the calling job |
| `Notification#buzz_text` | renders an alert as a chat line |
| `SmokeDispatch` | fires the NYK smoke workflow (shared with the Telegram path) |
| `bin/buzz-listen` | run the listener |
| `rake buzz:keygen` / `buzz:say` | generate identities, publish by hand |

The app already verified inbound Nostr logins (`NostrEventVerifier`,
`SchnorrVerifier`) for passwordless auth, so this reuses `bip-schnorr` and adds
no new dependency: `websocket-driver` was already in the bundle via Action Cable.

## Configuration

Nothing is sent until both of these are set, so the code is safe to merge ahead
of a relay:

```
BUZZ_RELAY_URL=wss://relay.example.com
BUZZ_PRIVATE_KEY=<64 hex chars>      # rake buzz:keygen
BUZZ_KEY_VLAD=<64 hex chars>         # optional: per-agent identity
```

Then `Notification.notify!(..., buzz: true, buzz_agent: "vlad")` mirrors an
alert into the room. The NYK smoke-test streak escalation already does.

## Listening (inbound)

```
bin/buzz-listen --channel agent44 --agent vlad
```

Commands are `!smoke` (fire the NY Kitchen check), `!status` (last run), `!help`.

Three rules keep this from being a hole in the side of the app, since a chat
message can now start a job:

1. **Only `!`-prefixed messages count.** Ordinary conversation in the room can
   never trip a command by accident.
2. **Only `BUZZ_ALLOWED_PUBKEYS` may run one**, and an unset allowlist means
   nobody can, rather than everybody. The listener warns loudly at boot if it is
   empty.
3. **Our own agents are ignored**, so a reply cannot trigger a reply.

`BUZZ_ALLOWED_PUBKEYS` holds *public* keys (comma separated). Note the corollary
of rule 3: never put a human's private key in `BUZZ_KEY_*` on the server, or the
listener treats them as itself and silently ignores everything they type.

The subscription sets `since` at connect time and remembers ids it has handled,
so a relay restart cannot replay yesterday's `!smoke` and run it again.

## Testing

`test/lib/buzz_test.rb` covers signing and serialization.
`test/lib/buzz_relay_test.rb` runs a throwaway relay in-process and exercises the
real handshake, the NIP-42 challenge, and the OK/rejection paths, so nothing is
published to a public relay from CI.

## Not done yet

- **No relay is running.** Buzz self-hosts on Postgres + Redis + S3/MinIO
  (`deploy/compose/`), which does not fit on the single Fly machine this app
  uses (SQLite on a per-machine volume, and `fly scale count > 1` would
  split-brain the data). A relay needs its own Fly app or a box elsewhere.
- **The listener is not deployed.** It is a foreground process
  (`bin/buzz-listen`); in prod it needs somewhere to live. SolidQueue runs
  inside puma here, so a long-lived socket does not fit the existing worker
  setup without thought.
- **Generic kind-1 notes.** Buzz has richer custom event kinds for channels,
  threads, and workflows; this uses the interoperable NIP-01 subset that any
  relay accepts. Channel membership semantics need the real kinds.
- **Commands are a fixed list**, not the Super Agent. Wiring `!ask` to
  `KitchenAi` is the obvious next move.
- Presence (kind 20001) is built but never published.

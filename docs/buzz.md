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
| `Buzz::Relay` | blocking WebSocket client: connect, auth, publish, wait for OK |
| `Buzz.say` | one-liner used by app code; a no-op when unconfigured |
| `BuzzPublishJob` | keeps the socket work off the calling job |
| `Notification#buzz_text` | renders an alert as a chat line |
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
- **Writes only.** Nothing subscribes yet, so you cannot type "run the smoke
  test" in a channel and have it happen. That is the interesting half, and it
  would replace the Telegram trigger.
- **Generic kind-1 notes.** Buzz has richer custom event kinds for channels,
  threads, and workflows; this uses the interoperable NIP-01 subset that any
  relay accepts. Channel membership semantics need the real kinds.
- Presence (kind 20001) is built but never published.

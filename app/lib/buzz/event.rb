# frozen_string_literal: true

# A signed NIP-01 event. Everything in Buzz is one of these: chat messages,
# reactions, workflow steps, git patches, presence. We only build the couple of
# kinds we need to speak as an agent.
module Buzz
  class Event
    # NIP-01 text note. Buzz has richer channel kinds, but a kind-1 note tagged
    # with the channel is the interoperable subset that any Nostr relay accepts,
    # which is what lets us test this pipeline without a Buzz relay in the loop.
    TEXT_NOTE = 1
    # NIP-42 relay auth, and Buzz's ephemeral presence kind from docs/remote-agents.md.
    AUTH      = 22242
    PRESENCE  = 20001

    attr_reader :kind, :content, :tags, :created_at, :pubkey, :id, :sig

    def self.note(keypair:, content:, channel: nil, tags: [])
      tags += [ [ "t", channel ] ] if channel.present?
      new(keypair: keypair, kind: TEXT_NOTE, content: content, tags: tags).sign
    end

    # NIP-42: the relay sends a challenge, we sign it back to prove we hold the key.
    def self.auth(keypair:, challenge:, relay_url:)
      new(
        keypair: keypair,
        kind:    AUTH,
        content: "",
        tags:    [ [ "relay", relay_url ], [ "challenge", challenge ] ]
      ).sign
    end

    def self.presence(keypair:, status: "online")
      new(keypair: keypair, kind: PRESENCE, content: status, tags: []).sign
    end

    # Does this event actually prove it came from the key it claims?
    #
    # A relay is supposed to reject forged events, but the allowlist is the only
    # thing between a chat message and a live GitHub dispatch, so we do not take
    # the relay's word for it: recompute the id from the payload and check the
    # signature ourselves. A buggy or hostile relay can then claim an
    # allowlisted pubkey all it likes and still not be believed.
    def self.valid?(event)
      id     = event["id"]
      pubkey = event["pubkey"]
      sig    = event["sig"]

      return false unless id.is_a?(String) && id.match?(/\A[0-9a-f]{64}\z/)
      return false unless pubkey.is_a?(String) && pubkey.match?(/\A[0-9a-f]{64}\z/)
      return false unless sig.is_a?(String) && sig.match?(/\A[0-9a-f]{128}\z/)

      serialized = [ 0, pubkey, event["created_at"], event["kind"], event["tags"], event["content"] ].to_json
      return false unless Digest::SHA256.hexdigest(serialized) == id

      SchnorrVerifier.verify(message_hex: id, pubkey_hex: pubkey, signature_hex: sig)
    rescue StandardError => e
      Rails.logger.warn("[buzz] event validation failed: #{e.class}: #{e.message}")
      false
    end

    def initialize(keypair:, kind:, content:, tags: [], created_at: Time.current.to_i)
      @keypair    = keypair
      @kind       = kind
      @content    = content.to_s
      @tags       = tags
      @created_at = created_at
      @pubkey     = keypair.public_key_hex
    end

    def sign
      @id  = Digest::SHA256.hexdigest(serialized)
      @sig = @keypair.sign(@id)
      self
    end

    def to_h
      { id: id, pubkey: pubkey, created_at: created_at, kind: kind, tags: tags, content: content, sig: sig }.stringify_keys
    end

    private

    # NIP-01 fixes both the field order and the JSON encoding of the digested
    # payload, so this array literal is the spec, not a style choice.
    def serialized
      [ 0, pubkey, created_at, kind, tags, content ].to_json
    end
  end
end

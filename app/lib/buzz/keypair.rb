# frozen_string_literal: true

# A Nostr (secp256k1 / BIP-340) keypair, which is how Buzz identifies every
# participant. Buzz treats agents as members rather than bots: each one gets its
# own key, its own channel memberships, and its own audit trail, so our jobs
# sign as e.g. "Vlad" instead of posting through one shared app token.
#
# The app already verifies inbound Nostr logins (NostrEventVerifier); this is
# the outbound half, where we hold the secret and sign.
module Buzz
  class Keypair
    class InvalidKey < StandardError; end

    GROUP = Schnorr::GROUP

    attr_reader :private_key_hex

    def self.generate
      new(SecureRandom.hex(32))
    end

    def initialize(private_key_hex)
      @private_key_hex = private_key_hex.to_s.strip.downcase
      raise InvalidKey, "private key must be 64 hex chars" unless @private_key_hex.match?(/\A[0-9a-f]{64}\z/)
      raise InvalidKey, "private key out of range" unless (1...GROUP.order).cover?(scalar)
    end

    # x-only public key: the 32-byte X coordinate, which is what a Nostr event's
    # "pubkey" field holds.
    def public_key_hex
      @public_key_hex ||= GROUP.generator.multiply_by_scalar(scalar).x.to_s(16).rjust(64, "0")
    end

    # message_hex is the event id (a SHA-256 digest, hex encoded).
    #
    # The key is handed over as hex and the message as raw bytes, which is not
    # arbitrary: Schnorr.sign sniffs whether its key argument is hex, and a
    # packed key whose bytes all land on ASCII hex characters gets misread as
    # hex and silently signs with the wrong scalar.
    def sign(message_hex)
      Schnorr.sign([ message_hex ].pack("H*"), private_key_hex).encode.unpack1("H*")
    end

    def to_s = "#<Buzz::Keypair #{public_key_hex[0, 12]}…>"
    alias inspect to_s

    private

    def scalar = @scalar ||= private_key_hex.to_i(16)
  end
end

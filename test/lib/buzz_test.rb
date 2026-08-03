# frozen_string_literal: true

require "test_helper"

# No network: these cover the signing/serialization we own. The relay round trip
# is exercised by hand with `rake buzz:say` against a real relay.
class BuzzKeypairTest < ActiveSupport::TestCase
  test "derives a 32-byte x-only pubkey and round-trips a signature" do
    keypair = Buzz::Keypair.new("01" * 32)

    assert_match(/\A[0-9a-f]{64}\z/, keypair.public_key_hex)

    digest = Digest::SHA256.hexdigest("hello buzz")
    sig    = keypair.sign(digest)

    assert SchnorrVerifier.verify(message_hex: digest, pubkey_hex: keypair.public_key_hex, signature_hex: sig)
  end

  test "generate produces distinct usable keys" do
    a = Buzz::Keypair.generate
    b = Buzz::Keypair.generate

    assert_not_equal a.public_key_hex, b.public_key_hex
    assert_match(/\A[0-9a-f]{64}\z/, a.private_key_hex)
  end

  test "rejects malformed private keys" do
    assert_raises(Buzz::Keypair::InvalidKey) { Buzz::Keypair.new("nope") }
    assert_raises(Buzz::Keypair::InvalidKey) { Buzz::Keypair.new("00" * 32) }
  end

  test "does not leak the secret when inspected" do
    keypair = Buzz::Keypair.new("ab" * 32)

    assert_not_includes keypair.inspect, keypair.private_key_hex
  end
end

class BuzzEventTest < ActiveSupport::TestCase
  setup { @keypair = Buzz::Keypair.new("42" * 32) }

  test "a note is a valid signed NIP-01 event" do
    event = Buzz::Event.note(keypair: @keypair, content: "smoke test passed", channel: "nyk")

    assert_equal Buzz::Event::TEXT_NOTE, event.kind
    assert_equal @keypair.public_key_hex, event.pubkey
    assert_includes event.tags, [ "t", "nyk" ]

    # The id must be the SHA-256 of the canonical serialization, and the
    # signature must verify against it.
    expected_id = Digest::SHA256.hexdigest([ 0, event.pubkey, event.created_at, event.kind, event.tags, event.content ].to_json)
    assert_equal expected_id, event.id
    assert SchnorrVerifier.verify(message_hex: event.id, pubkey_hex: event.pubkey, signature_hex: event.sig)
  end

  test "an auth event satisfies our own NIP-42 verifier" do
    event = Buzz::Event.auth(keypair: @keypair, challenge: "chal-123", relay_url: "wss://relay.example")

    assert NostrEventVerifier.verify(signed_event: event.to_h, expected_challenge: "chal-123")
    assert_not NostrEventVerifier.verify(signed_event: event.to_h, expected_challenge: "different")
  end

  test "serializes to the wire shape a relay expects" do
    event = Buzz::Event.note(keypair: @keypair, content: "hi")

    assert_equal %w[id pubkey created_at kind tags content sig].sort, event.to_h.keys.sort
  end
end

class BuzzConfigTest < ActiveSupport::TestCase
  test "is disabled and inert without configuration" do
    with_env("BUZZ_RELAY_URL" => nil, "BUZZ_PRIVATE_KEY" => nil) do
      assert_not Buzz.enabled?
      assert_not Buzz.say("should not raise")
    end
  end

  test "prefers a named agent key over the shared app key" do
    with_env("BUZZ_PRIVATE_KEY" => "11" * 32, "BUZZ_KEY_VLAD" => "22" * 32) do
      assert_equal Buzz::Keypair.new("22" * 32).public_key_hex, Buzz.keypair_for("vlad").public_key_hex
      assert_equal Buzz::Keypair.new("11" * 32).public_key_hex, Buzz.keypair_for("carson").public_key_hex
    end
  end

  private

  def with_env(vars)
    original = ENV.to_h.slice(*vars.keys)
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    vars.each_key { |k| original.key?(k) ? ENV[k] = original[k] : ENV.delete(k) }
  end
end

class NotificationBuzzTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "renders an alert as a chat line" do
    notification = Notification.new(level: "error", source: "smoke", title: "Calendar check failed", body: "3 runs in a row")

    assert_equal "🔴 Calendar check failed\n3 runs in a row", notification.buzz_text
  end

  test "does not enqueue a publish when Buzz is unconfigured" do
    assert_no_enqueued_jobs(only: BuzzPublishJob) do
      Notification.notify!(level: "info", source: "test", title: "hello", buzz: true)
    end
  end
end

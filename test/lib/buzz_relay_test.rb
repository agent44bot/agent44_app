# frozen_string_literal: true

require "test_helper"
require "websocket/driver"
require "socket"

# Exercises the real WebSocket round trip against a throwaway relay running in
# this process: handshake, NIP-42 challenge, re-publish, OK. No network, and
# nothing is posted to a public relay.
class BuzzRelayTest < ActiveSupport::TestCase
  # Minimal Nostr relay. `require_auth` makes it behave like a Buzz relay that
  # refuses writes until the client proves it holds the key.
  class FakeRelay
    CHALLENGE = "test-challenge-123"

    attr_reader :received, :auth_events

    def initialize(require_auth: false, accept: true)
      @require_auth = require_auth
      @accept       = accept
      @received     = []
      @auth_events  = []
      @server       = TCPServer.new("127.0.0.1", 0)
      @thread       = Thread.new { serve }
    end

    def url = "ws://127.0.0.1:#{@server.addr[1]}"

    def shutdown
      @thread&.kill
      @server&.close
    rescue StandardError
      nil
    end

    private

    def serve
      socket = @server.accept
      driver = WebSocket::Driver.server(Adapter.new(socket))
      driver.on(:connect) { WebSocket::Driver.websocket?(driver.env) && driver.start }
      driver.on(:message) { |event| handle(driver, JSON.parse(event.data)) }

      driver.parse(socket.readpartial(16_384)) while true
    rescue StandardError
      nil
    end

    def handle(driver, message)
      type, payload = message

      case type
      when "EVENT"
        if @require_auth && !@authed
          driver.text(JSON.generate([ "AUTH", CHALLENGE ]))
        else
          @received << payload
          reason = @accept ? "" : "blocked: not a member"
          driver.text(JSON.generate([ "OK", payload["id"], @accept, reason ]))
        end
      when "AUTH"
        @auth_events << payload
        @authed = NostrEventVerifier.verify(signed_event: payload, expected_challenge: CHALLENGE)
      end
    end

    Adapter = Struct.new(:io) do
      def write(data) = io.write(data)
    end
  end

  setup do
    @keypair = Buzz::Keypair.generate
  end

  teardown do
    @relay&.shutdown
  end

  test "publishes a signed event and resolves on the relay's OK" do
    @relay = FakeRelay.new
    event  = Buzz::Event.note(keypair: @keypair, content: "smoke test passed", channel: "agent44")

    assert Buzz::Relay.new(url: @relay.url, keypair: @keypair, timeout: 5).publish(event)

    received = @relay.received.sole
    assert_equal event.id, received["id"]
    assert_equal "smoke test passed", received["content"]
    assert_equal @keypair.public_key_hex, received["pubkey"]
  end

  test "answers a NIP-42 challenge and retries the publish" do
    @relay = FakeRelay.new(require_auth: true)
    event  = Buzz::Event.note(keypair: @keypair, content: "hello")

    assert Buzz::Relay.new(url: @relay.url, keypair: @keypair, timeout: 5).publish(event)

    # The relay only accepted the event after verifying an auth event signed by
    # the same key, which is the property that makes an agent's posts its own.
    assert_equal 1, @relay.auth_events.size
    assert_equal @keypair.public_key_hex, @relay.auth_events.first["pubkey"]
    assert_equal event.id, @relay.received.sole["id"]
  end

  test "raises with the relay's reason when the event is rejected" do
    @relay = FakeRelay.new(accept: false)
    event  = Buzz::Event.note(keypair: @keypair, content: "nope")

    error = assert_raises(Buzz::Relay::Rejected) do
      Buzz::Relay.new(url: @relay.url, keypair: @keypair, timeout: 5).publish(event)
    end
    assert_match(/not a member/, error.message)
  end

  test "times out instead of hanging when nothing answers" do
    server = TCPServer.new("127.0.0.1", 0) # accepts, never speaks WebSocket
    url    = "ws://127.0.0.1:#{server.addr[1]}"

    assert_raises(Buzz::Relay::Timeout) do
      Buzz::Relay.new(url: url, keypair: @keypair, timeout: 1).publish(Buzz::Event.note(keypair: @keypair, content: "x"))
    end
  ensure
    server&.close
  end

  test "Buzz.say swallows relay failures so callers keep working" do
    @relay = FakeRelay.new(accept: false)

    ENV["BUZZ_RELAY_URL"]   = @relay.url
    ENV["BUZZ_PRIVATE_KEY"] = @keypair.private_key_hex

    assert_not Buzz.say("this will be rejected")
  ensure
    ENV.delete("BUZZ_RELAY_URL")
    ENV.delete("BUZZ_PRIVATE_KEY")
  end
end

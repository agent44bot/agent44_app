# frozen_string_literal: true

require "test_helper"
require "websocket/driver"
require "socket"

# Drives the listen path against a throwaway relay in this process: REQ filter,
# NIP-42 challenge, event delivery, and duplicate suppression.
class BuzzSubscriberTest < ActiveSupport::TestCase
  class FakeRelay
    CHALLENGE = "sub-challenge"

    attr_reader :requests

    def initialize(require_auth: false)
      @require_auth = require_auth
      @requests     = Queue.new
      @drivers      = Queue.new
      @server       = TCPServer.new("127.0.0.1", 0)
      @thread       = Thread.new { serve }
    end

    def url = "ws://127.0.0.1:#{@server.addr[1]}"

    # Waits for the client's REQ so tests never push before it is subscribed.
    def await_subscription(timeout: 5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      until @requests.size.positive?
        raise "client never subscribed" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 0.05
      end
      @requests.pop
    end

    def push(event, sub_id: Buzz::Subscriber::SUBSCRIPTION_ID)
      @driver.text(JSON.generate([ "EVENT", sub_id, event ]))
    end

    def shutdown
      @thread&.kill
      @server&.close
    rescue StandardError
      nil
    end

    private

    def serve
      socket  = @server.accept
      @driver = WebSocket::Driver.server(Adapter.new(socket))
      @driver.on(:connect) { @driver.start }
      @driver.on(:message) { |e| handle(JSON.parse(e.data)) }
      @driver.parse(socket.readpartial(16_384)) while true
    rescue StandardError
      nil
    end

    def handle(message)
      type, *rest = message
      case type
      when "REQ"
        if @require_auth && !@authed
          @driver.text(JSON.generate([ "AUTH", CHALLENGE ]))
        else
          @requests << rest.last # the filter
        end
      when "AUTH"
        @authed = NostrEventVerifier.verify(signed_event: rest.first, expected_challenge: CHALLENGE)
      end
    end

    Adapter = Struct.new(:io) do
      def write(data) = io.write(data)
    end
  end

  setup do
    @keypair = Buzz::Keypair.generate
    @relay   = FakeRelay.new
  end

  teardown { @relay&.shutdown }

  # Runs the (blocking) subscriber on a thread and collects what it yields.
  def collect(expected:, subscriber: nil, timeout: 5)
    received = Queue.new
    sub = subscriber || Buzz::Subscriber.new(url: @relay.url, keypair: @keypair, channel: "agent44", logger: Logger.new(File::NULL))
    thread = Thread.new { sub.listen { |event| received << event } }

    filter = @relay.await_subscription
    yield filter

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    out = []
    while out.size < expected && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      out << received.pop(true) rescue sleep 0.05
    end
    out
  ensure
    thread&.kill
  end

  test "subscribes with a channel filter that excludes stored history" do
    captured = nil
    collect(expected: 0) { |filter| captured = filter }

    assert_equal [ 1 ], captured["kinds"]
    assert_equal [ "agent44" ], captured["#t"]
    # `since` is what stops a restart from replaying and re-running old commands.
    assert captured["since"] >= 5.seconds.ago.to_i
  end

  # A message as some other participant in the room would sign it.
  def signed(content)
    Buzz::Event.note(keypair: Buzz::Keypair.generate, content: content, channel: "agent44").to_h
  end

  test "yields events pushed by the relay" do
    events = collect(expected: 1) { @relay.push(signed("!help")) }

    assert_equal 1, events.size
    assert_equal "!help", events.first["content"]
  end

  test "suppresses a duplicate id so a command cannot run twice" do
    duplicate = signed("!smoke")

    events = collect(expected: 2, timeout: 2) do
      3.times { @relay.push(duplicate) }
    end

    assert_equal 1, events.size
  end

  test "answers a NIP-42 challenge before subscribing" do
    @relay.shutdown
    @relay = FakeRelay.new(require_auth: true)

    events = collect(expected: 1) { @relay.push(signed("!status")) }

    assert_equal "!status", events.first["content"]
  end

  # Anything the relay sends that does not prove it came from the key it claims
  # is dropped here, so nothing downstream has to re-check it.
  test "drops an event whose signature does not match" do
    forged = signed("!smoke").merge("pubkey" => Buzz::Keypair.generate.public_key_hex)

    events = collect(expected: 1, timeout: 2) { @relay.push(forged) }

    assert_empty events
  end
end

# frozen_string_literal: true

require "websocket/driver"
require "socket"
require "openssl"
require "uri"

# A minimal blocking Nostr relay client: connect, answer the NIP-42 auth
# challenge, publish an event, wait for the relay's OK. Built on websocket-driver
# (already in the bundle via Action Cable) so this adds no new dependency.
#
# Blocking-and-short-lived is the right shape here because every caller is a
# background job publishing one event, not a long-lived subscriber.
module Buzz
  class Relay
    class Error < StandardError; end
    class Timeout < Error; end
    class Rejected < Error; end

    DEFAULT_TIMEOUT = 10 # seconds for the whole publish round trip

    def initialize(url:, keypair:, timeout: DEFAULT_TIMEOUT, logger: Rails.logger)
      @url      = url
      @keypair  = keypair
      @timeout  = timeout
      @logger   = logger
      @deadline = nil
    end

    # Publishes one signed event and returns true once the relay ACKs it.
    # Raises Rejected if the relay says no, Timeout if it never answers.
    def publish(event)
      @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
      connect

      send_frame([ "EVENT", event.to_h ])
      pump do |message|
        case message[0]
        when "OK"
          # ["OK", <event id>, <accepted>, <message>]
          next unless message[1] == event.id
          raise Rejected, "relay rejected event: #{message[3]}" unless message[2]
          return true
        when "AUTH"
          # The relay wants NIP-42 before it accepts writes. Answer, then resend.
          authenticate(message[1])
          send_frame([ "EVENT", event.to_h ])
        when "NOTICE"
          @logger.warn("[buzz] relay notice: #{message[1]}")
        end
      end
    ensure
      close
    end

    private

    def authenticate(challenge)
      send_frame([ "AUTH", Event.auth(keypair: @keypair, challenge: challenge, relay_url: @url).to_h ])
    end

    def connect
      uri    = URI.parse(@url)
      secure = uri.scheme == "wss"
      tcp    = TCPSocket.new(uri.host, uri.port || (secure ? 443 : 80))

      @io = if secure
        ssl = OpenSSL::SSL::SSLSocket.new(tcp, ssl_context)
        ssl.hostname = uri.host # SNI
        ssl.connect
        ssl.post_connection_check(uri.host)
        ssl
      else
        tcp
      end

      @open   = false
      @queue  = []
      @driver = WebSocket::Driver.client(Adapter.new(@io, @url))
      @driver.on(:open)    { @open = true }
      @driver.on(:message) { |e| @queue << e.data }
      @driver.on(:error)   { |e| raise Error, e.message }
      @driver.start

      read_once until @open
    end

    # Yields each decoded relay message until the caller's block returns or we
    # run out of time.
    def pump
      loop do
        while (data = @queue.shift)
          yield JSON.parse(data)
        end

        read_once
      end
    end

    # One bounded read: block on the socket, hand whatever arrives to the driver,
    # which fills @queue via the :message callback.
    def read_once
      raise Timeout, "no response from #{@url} within #{@timeout}s" if remaining <= 0
      raise Timeout, "no response from #{@url} within #{@timeout}s" unless IO.select([ @io ], nil, nil, remaining)

      @driver.parse(read_available)
    end

    def read_available
      @io.read_nonblock(16_384)
    rescue IO::WaitReadable
      ""
    rescue EOFError, OpenSSL::SSL::SSLError => e
      raise Error, "relay connection lost: #{e.class}"
    end

    def send_frame(payload)
      @driver.text(JSON.generate(payload))
    end

    def remaining = @deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def ssl_context
      OpenSSL::SSL::SSLContext.new.tap { |ctx| ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER) }
    end

    def close
      @driver&.close
      @io&.close
    rescue StandardError
      nil
    end

    # websocket-driver talks to a socket object that exposes #url and #write.
    Adapter = Struct.new(:io, :url) do
      def write(data) = io.write(data)
    end
  end
end

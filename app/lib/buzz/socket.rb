# frozen_string_literal: true

require "websocket/driver"
require "socket"
require "openssl"
require "uri"

module Buzz
  # Low-level WebSocket plumbing shared by the publish (Relay) and listen
  # (Subscriber) paths: TCP/TLS, the handshake, and JSON frames in and out.
  #
  # Publishing wants a hard deadline on the whole round trip; listening wants to
  # sit and wait indefinitely. Both are the same socket, so `timeout: nil` means
  # "block until something arrives".
  class Socket
    class Error < StandardError; end
    class Timeout < Error; end

    attr_reader :url

    def initialize(url)
      @url   = url
      @queue = []
      @open  = false
    end

    def open!(timeout: 10)
      uri    = URI.parse(@url)
      secure = uri.scheme == "wss"
      tcp    = TCPSocket.new(uri.host, uri.port || (secure ? 443 : 80))
      @io    = secure ? wrap_tls(tcp, uri.host) : tcp

      @driver = WebSocket::Driver.client(Adapter.new(@io, @url))
      @driver.on(:open)    { @open = true }
      @driver.on(:message) { |e| @queue << e.data }
      @driver.on(:error)   { |e| raise Error, e.message }
      @driver.start

      deadline = timeout && monotonic + timeout
      read_once(deadline) until @open
      self
    end

    def send_json(payload)
      @driver.text(JSON.generate(payload))
    end

    # Yields each decoded relay message until the caller's block breaks or
    # returns. `timeout` bounds the total wait, not each message.
    def each_message(timeout: nil)
      deadline = timeout && monotonic + timeout
      loop do
        while (data = @queue.shift)
          yield JSON.parse(data)
        end

        read_once(deadline)
      end
    end

    def close
      @driver&.close
      @io&.close
    rescue StandardError
      nil
    end

    private

    def read_once(deadline)
      wait = deadline && deadline - monotonic
      raise Timeout, "no response from #{@url}" if wait && wait <= 0
      raise Timeout, "no response from #{@url}" unless IO.select([ @io ], nil, nil, wait)

      @driver.parse(read_available)
    end

    def read_available
      @io.read_nonblock(16_384)
    rescue IO::WaitReadable
      ""
    rescue EOFError, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
      raise Error, "relay connection lost: #{e.class}"
    end

    def wrap_tls(tcp, host)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
      ssl = OpenSSL::SSL::SSLSocket.new(tcp, ctx)
      ssl.hostname = host # SNI
      ssl.connect
      ssl.post_connection_check(host)
      ssl
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # websocket-driver talks to a socket object exposing #url and #write.
    Adapter = Struct.new(:io, :url) do
      def write(data) = io.write(data)
    end
  end
end

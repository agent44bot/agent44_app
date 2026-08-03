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
      uri      = URI.parse(@url)
      secure   = uri.scheme == "wss"
      deadline = timeout && monotonic + timeout

      # The connect itself is inside the deadline. An unreachable or firewalled
      # host drops packets silently, and a bare TCPSocket.new would sit there for
      # the OS-level connect timeout (minutes), far past the caller's budget.
      # That matters because production runs few worker threads, so one wedged
      # publish can hold up unrelated jobs.
      # ::Socket is Ruby's, not Buzz::Socket.
      tcp = begin
        ::Socket.tcp(uri.host, uri.port || (secure ? 443 : 80), connect_timeout: seconds_left(deadline))
      rescue Errno::ETIMEDOUT, IO::TimeoutError => e
        # Surfaced as our own Timeout so callers have one thing to rescue,
        # whichever way the runtime reports a stalled connect.
        raise Timeout, "could not connect to #{@url}: #{e.class}"
      end
      @io = secure ? wrap_tls(tcp, uri.host, deadline) : tcp

      @driver = WebSocket::Driver.client(Adapter.new(@io, @url))
      @driver.on(:open)    { @open = true }
      @driver.on(:message) { |e| @queue << e.data }
      @driver.on(:error)   { |e| raise Error, e.message }
      @driver.start

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
      wait = seconds_left(deadline)
      raise Timeout, "no response from #{@url}" if wait && wait <= 0
      raise Timeout, "no response from #{@url}" unless IO.select([ @io ], nil, nil, wait)

      @driver.parse(read_available)
    end

    # Seconds remaining before `deadline`, or nil for "wait indefinitely".
    def seconds_left(deadline)
      deadline && deadline - monotonic
    end

    def read_available
      @io.read_nonblock(16_384)
    rescue IO::WaitReadable
      ""
    rescue EOFError, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
      raise Error, "relay connection lost: #{e.class}"
    end

    # The TLS handshake is bounded too: a host that completes the TCP connect and
    # then stalls mid-handshake would otherwise hang just as long.
    def wrap_tls(tcp, host, deadline)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
      ssl = OpenSSL::SSL::SSLSocket.new(tcp, ctx)
      ssl.hostname = host # SNI

      begin
        ssl.connect_nonblock
      rescue IO::WaitReadable
        await(tcp, :read, deadline)
        retry
      rescue IO::WaitWritable
        await(tcp, :write, deadline)
        retry
      end

      ssl.post_connection_check(host)
      ssl
    end

    def await(io, direction, deadline)
      wait = seconds_left(deadline)
      raise Timeout, "TLS handshake with #{@url} timed out" if wait && wait <= 0

      ready = direction == :read ? IO.select([ io ], nil, nil, wait) : IO.select(nil, [ io ], nil, wait)
      raise Timeout, "TLS handshake with #{@url} timed out" unless ready
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # websocket-driver talks to a socket object exposing #url and #write.
    Adapter = Struct.new(:io, :url) do
      def write(data) = io.write(data)
    end
  end
end

# frozen_string_literal: true

# Publishes one signed event and waits for the relay to acknowledge it:
# connect, answer the NIP-42 challenge if asked, send, wait for OK.
#
# Blocking and short-lived is the right shape here because every caller is a
# background job publishing a single event, not a long-lived subscriber.
module Buzz
  class Relay
    class Error < Socket::Error; end
    class Rejected < Error; end
    Timeout = Socket::Timeout

    DEFAULT_TIMEOUT = 10 # seconds for the whole publish round trip

    def initialize(url:, keypair:, timeout: DEFAULT_TIMEOUT, logger: Rails.logger)
      @url     = url
      @keypair = keypair
      @timeout = timeout
      @logger  = logger
    end

    # Returns true once the relay ACKs the event. Raises Rejected if the relay
    # says no, Timeout if it never answers.
    # A relay that requires NIP-42 answers the first EVENT with both a refusal
    # and a challenge:
    #   ["OK", <id>, false, "auth-required: not authenticated"]
    #   ["AUTH", <challenge>]
    # The refusal is an instruction, not a verdict, so it is only treated as a
    # real rejection once we have already authenticated.
    AUTH_REQUIRED = /\A(auth-required|restricted)/

    def publish(event)
      socket        = Socket.new(@url).open!(timeout: @timeout)
      authenticated = false
      refusal       = nil
      socket.send_json([ "EVENT", event.to_h ])

      socket.each_message(timeout: @timeout) do |message|
        case message[0]
        when "OK"
          # ["OK", <event id>, <accepted>, <message>]
          next unless message[1] == event.id
          return true if message[2]

          reason = message[3].to_s
          # Both attempts carry the same event id, so an auth-required refusal
          # cannot be pinned to one of them: it may be the stale answer to the
          # pre-auth attempt, arriving after we have already authenticated.
          # Never a verdict, then. Keep waiting, and let the timeout report it.
          if reason.match?(AUTH_REQUIRED)
            refusal = reason
            next
          end

          raise Rejected, "relay rejected event: #{reason}"
        when "AUTH"
          next if authenticated # one challenge is enough; do not ping-pong

          authenticated = true
          socket.send_json([ "AUTH", Event.auth(keypair: @keypair, challenge: message[1], relay_url: @url).to_h ])
          socket.send_json([ "EVENT", event.to_h ])
        when "NOTICE"
          @logger.warn("[buzz] relay notice: #{message[1]}")
        end
      end
    rescue Timeout
      # If the only thing the relay ever said was "authenticate first", that is
      # the useful error, not "nothing answered".
      raise Rejected, "relay refused the event: #{refusal}" if refusal

      raise
    ensure
      socket&.close
    end
  end
end

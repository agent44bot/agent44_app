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
    def publish(event)
      socket = Socket.new(@url).open!(timeout: @timeout)
      socket.send_json([ "EVENT", event.to_h ])

      socket.each_message(timeout: @timeout) do |message|
        case message[0]
        when "OK"
          # ["OK", <event id>, <accepted>, <message>]
          next unless message[1] == event.id
          raise Rejected, "relay rejected event: #{message[3]}" unless message[2]
          return true
        when "AUTH"
          # The relay wants NIP-42 before it accepts writes. Answer, then resend.
          socket.send_json([ "AUTH", Event.auth(keypair: @keypair, challenge: message[1], relay_url: @url).to_h ])
          socket.send_json([ "EVENT", event.to_h ])
        when "NOTICE"
          @logger.warn("[buzz] relay notice: #{message[1]}")
        end
      end
    ensure
      socket&.close
    end
  end
end

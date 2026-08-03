# frozen_string_literal: true

# The inbound half: hold a connection open and yield channel messages as they
# arrive, so a person can type in a Buzz room and the app reacts.
#
# Two things keep this from misbehaving:
#   - `since` is set at connect time, so the relay's stored history is not
#     replayed and a restart cannot re-run yesterday's commands.
#   - ids we have already handled are remembered, because a relay may resend an
#     event and a duplicate here means running a job twice.
module Buzz
  class Subscriber
    SUBSCRIPTION_ID = "agent44-commands"
    SEEN_LIMIT      = 500

    def initialize(url:, keypair:, channel:, logger: Rails.logger)
      @url     = url
      @keypair = keypair
      @channel = channel
      @logger  = logger
      @seen    = []
    end

    # Yields each new kind-1 event in the channel as a plain hash. Blocks until
    # the connection drops, which it lets the caller handle (see Listener).
    def listen
      socket = Socket.new(@url).open!
      socket.send_json(request_frame)
      @logger.info("[buzz] listening on #{@url} ##{@channel}")

      socket.each_message do |message|
        case message[0]
        when "EVENT"
          # ["EVENT", <sub id>, <event>]
          event = message[2]
          next unless event.is_a?(Hash)
          next if duplicate?(event["id"])
          # Nothing unsigned gets past the boundary, so callers never have to
          # wonder whether an event is trustworthy.
          unless Event.valid?(event)
            @logger.warn("[buzz] dropped an event that failed signature validation")
            next
          end
          yield event
        when "AUTH"
          socket.send_json([ "AUTH", Event.auth(keypair: @keypair, challenge: message[1], relay_url: @url).to_h ])
          socket.send_json(request_frame)
        when "CLOSED"
          raise Socket::Error, "relay closed the subscription: #{message[2]}"
        when "NOTICE"
          @logger.warn("[buzz] relay notice: #{message[1]}")
        end
      end
    ensure
      socket&.close
    end

    private

    def request_frame
      [ "REQ", SUBSCRIPTION_ID, { "kinds" => [ Event::TEXT_NOTE ], "#t" => [ @channel ], "since" => Time.current.to_i } ]
    end

    def duplicate?(id)
      return true if id.blank?
      return true if @seen.include?(id)

      @seen.push(id)
      @seen.shift while @seen.size > SEEN_LIMIT
      false
    end
  end
end

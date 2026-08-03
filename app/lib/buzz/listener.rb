# frozen_string_literal: true

# Long-running glue: subscribe to a channel, route each message, post the reply.
#
# Relays drop connections (restarts, idle timeouts, network), and a listener
# that dies on the first hiccup is not a listener, so this reconnects with
# backoff and keeps going.
module Buzz
  class Listener
    MIN_BACKOFF = 1
    MAX_BACKOFF = 60

    def initialize(channel: Buzz::DEFAULT_CHANNEL, agent: nil, logger: Rails.logger)
      @channel = channel
      @agent   = agent
      @logger  = logger
      @router  = CommandRouter.new(logger: logger)
      @running = true
    end

    def stop = @running = false

    def run
      unless Buzz.enabled?
        @logger.error("[buzz] not configured, set BUZZ_RELAY_URL and BUZZ_PRIVATE_KEY")
        return
      end

      if CommandRouter.allowed_pubkeys.empty?
        @logger.warn("[buzz] BUZZ_ALLOWED_PUBKEYS is empty, so every command will be refused")
      end

      backoff = MIN_BACKOFF

      while @running
        begin
          subscriber.listen do |event|
            backoff = MIN_BACKOFF # a delivered event proves the link is healthy
            handle(event)
          end
        rescue Socket::Error, SystemCallError => e
          break unless @running
          @logger.warn("[buzz] connection lost (#{e.message}), reconnecting in #{backoff}s")
          sleep backoff
          backoff = [ backoff * 2, MAX_BACKOFF ].min
        end
      end
    end

    private

    def subscriber
      Subscriber.new(url: Buzz.relay_url, keypair: Buzz.keypair_for(@agent), channel: @channel, logger: @logger)
    end

    # One bad message must not kill the listener, so failures are logged and the
    # loop continues.
    def handle(event)
      reply = @router.call(event)
      return if reply.blank?

      Buzz.say(reply, agent: @agent, channel: @channel)
    rescue StandardError => e
      @logger.error("[buzz] handling #{event['id'].to_s[0, 12]}… failed: #{e.class}: #{e.message}")
    end
  end
end

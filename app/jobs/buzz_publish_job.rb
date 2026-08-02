# frozen_string_literal: true

# Publishing talks to the relay over a socket, so it goes through the queue
# rather than blocking whatever job or request produced the message.
class BuzzPublishJob < ApplicationJob
  queue_as :default

  def perform(text, agent: nil, channel: Buzz::DEFAULT_CHANNEL)
    Buzz.say(text, agent: agent, channel: channel)
  end
end

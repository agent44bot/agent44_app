# frozen_string_literal: true

# Buzz (github.com/block/buzz) is Block's open-source Nostr workspace, where
# humans and agents share one room and every message is a signed event on a
# relay you host. This module is our side of that: the app's agents (Vlad's
# smoke tests, Carson's reports, Echo's drafts) can post into a Buzz channel
# under their own keys instead of only fanning out to email and push.
#
# Wiring: set BUZZ_RELAY_URL and BUZZ_PRIVATE_KEY. Give an agent its own
# identity with BUZZ_KEY_<AGENT> (e.g. BUZZ_KEY_VLAD); otherwise it signs with
# the shared app key. With nothing set, every call is a no-op, so this is safe
# to leave in place before a relay exists.
module Buzz
  DEFAULT_CHANNEL = "agent44"

  module_function

  def enabled? = relay_url.present? && ENV["BUZZ_PRIVATE_KEY"].present?

  def relay_url = ENV["BUZZ_RELAY_URL"].presence

  # Named agents get their own keypair when one is configured, which is what
  # earns them a distinct identity and audit trail in the room.
  def keypair_for(agent = nil)
    hex = ENV["BUZZ_KEY_#{agent.to_s.upcase}"].presence if agent.present?
    hex ||= ENV["BUZZ_PRIVATE_KEY"].presence
    hex && Keypair.new(hex)
  end

  # Every pubkey this app can sign as. The listener uses it to ignore its own
  # messages, which is what stops a reply from triggering another reply.
  def own_pubkeys
    keys = ENV.select { |name, value| name.start_with?("BUZZ_KEY_") && value.present? }.values
    keys << ENV["BUZZ_PRIVATE_KEY"] if ENV["BUZZ_PRIVATE_KEY"].present?
    keys.filter_map do |hex|
      Keypair.new(hex).public_key_hex
    rescue Keypair::InvalidKey
      nil
    end.uniq
  end

  # Post a message into a Buzz channel as `agent`. Returns false (and logs)
  # rather than raising, so a relay hiccup never takes down the job that was
  # only trying to say something.
  def say(text, agent: nil, channel: DEFAULT_CHANNEL)
    return false unless enabled?

    keypair = keypair_for(agent)
    return false unless keypair

    event = Event.note(keypair: keypair, content: text, channel: channel)
    Relay.new(url: relay_url, keypair: keypair).publish(event)
  rescue StandardError => e
    Rails.logger.warn("[buzz] publish failed (#{agent || 'app'} → ##{channel}): #{e.class}: #{e.message}")
    false
  end
end

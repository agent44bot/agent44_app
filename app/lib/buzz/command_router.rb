# frozen_string_literal: true

# Turns a chat message into an action.
#
# This is the part that can actually do things on someone's say-so, so it is
# deliberately narrow:
#   - only messages starting with "!" count, so ordinary conversation in the
#     room can never trip a command by accident
#   - only pubkeys on BUZZ_ALLOWED_PUBKEYS may run one, and an unset allowlist
#     means nobody can, rather than everybody
#   - our own agents' messages are ignored, so a reply cannot trigger a reply
module Buzz
  class CommandRouter
    PREFIX = "!"

    def initialize(logger: Rails.logger)
      @logger = logger
    end

    # Returns a reply string to post back, or nil to stay silent.
    def call(event)
      text = event["content"].to_s.strip
      return nil unless text.start_with?(PREFIX)

      pubkey = event["pubkey"].to_s.downcase
      return nil if Buzz.own_pubkeys.include?(pubkey) # never answer ourselves

      command, _rest = text.delete_prefix(PREFIX).strip.split(/\s+/, 2)
      command = command.to_s.downcase
      return nil if command.blank? # a bare "!" is not an attempt at a command

      unless authorized?(pubkey)
        @logger.warn("[buzz] refused !#{command} from unlisted pubkey #{pubkey[0, 12]}…")
        return "Sorry, #{pubkey[0, 8]}… is not on the command allowlist."
      end

      @logger.info("[buzz] running !#{command} for #{pubkey[0, 12]}…")

      case command
      when "smoke"  then run_smoke(pubkey)
      when "status" then smoke_status
      when "help"   then help
      else "Unknown command !#{command}. #{help}"
      end
    end

    def self.allowed_pubkeys
      ENV["BUZZ_ALLOWED_PUBKEYS"].to_s.split(",").filter_map { |k| k.strip.downcase.presence }
    end

    private

    def authorized?(pubkey)
      self.class.allowed_pubkeys.include?(pubkey)
    end

    def help
      "Commands: !smoke (run the NY Kitchen check), !status (last run), !help"
    end

    def run_smoke(pubkey)
      case SmokeDispatch.trigger!(requested_by: "#{pubkey[0, 8]}… via Buzz", via: "Buzz")
      when :ok       then "Kicked off the NY Kitchen smoke test. I'll post the result here when it lands."
      when :no_token then "I can't trigger it: GITHUB_PAT isn't set on this instance."
      else "Tried to trigger the smoke test but GitHub rejected the request. Check the logs."
      end
    end

    def smoke_status
      run = SmokeTestRun.nyk.recent.first
      return "No NY Kitchen runs recorded yet." unless run

      "Last run: #{run.name} #{run.status} #{time_ago_in_words(run.started_at)} ago."
    end

    def time_ago_in_words(time)
      ActionController::Base.helpers.time_ago_in_words(time)
    end
  end
end

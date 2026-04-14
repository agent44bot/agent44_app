module Api
  module V1
    class TelegramWebhookController < ApplicationController
      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      # POST /api/v1/telegram/webhook
      # Receives Telegram bot updates and auto-updates agent statuses
      def create
        message_text = params.dig(:message, :text) || ""
        bot_reply = params.dig(:message, :from, :is_bot)

        # Only process bot messages (from our agent bot)
        if bot_reply && message_text.present?
          detect_agent_status(message_text)
        end

        head :ok
      end

      private

      AGENT_NAMES = {
        "ripley"  => "Ripley",
        "neo"     => "Neo 💻",
        "russ"    => "Russ 🔒",
        "vlad"    => "Vlad ✅",
        "knox"    => "Knox 🔒",
        "jr"      => "Jr 🐣",
        "scout"   => "Scout 🔭"
      }.freeze

      BUSY_PATTERNS = [
        /(\w+)\s+is\s+(?:already\s+)?(?:on it|working|scanning|running|checking|analyzing|delegating|coordinating)/i,
        /(?:spawned|assigned|tasked|delegated)\s+(?:to\s+)?(\w+)/i,
        /(\w+)\s+(?:is\s+)?(?:now\s+)?(?:busy|processing|executing)/i
      ].freeze

      DONE_PATTERNS = [
        /(\w+)\s+(?:has\s+)?(?:finished|completed|done|wrapped up)/i,
        /(\w+)(?:'s)?\s+(?:scan|task|work|report)\s+(?:is\s+)?(?:complete|done|finished|ready)/i,
        /results?\s+from\s+(\w+)/i
      ].freeze

      ERROR_PATTERNS = [
        /(\w+)\s+(?:failed|errored|crashed|timed out)/i,
        /(?:error|failure)\s+(?:from|with|in)\s+(\w+)/i
      ].freeze

      def detect_agent_status(text)
        # Check for errors first
        ERROR_PATTERNS.each do |pattern|
          if (match = text.match(pattern))
            update_agent(match[1], "error", extract_task(text))
            return
          end
        end

        # Check for completion
        DONE_PATTERNS.each do |pattern|
          if (match = text.match(pattern))
            update_agent(match[1], "online")
            return
          end
        end

        # Check for busy/working
        BUSY_PATTERNS.each do |pattern|
          if (match = text.match(pattern))
            update_agent(match[1], "busy", extract_task(text))
            return
          end
        end
      end

      def update_agent(name_fragment, status, task = nil)
        key = name_fragment.downcase.strip
        full_name = AGENT_NAMES[key]
        return unless full_name

        agent = Agent.find_by(name: full_name)
        return unless agent

        attrs = { status: status, last_active_at: Time.current }
        attrs[:current_task] = task if status == "busy" || status == "error"
        attrs[:current_task] = nil if status == "online"

        agent.update!(attrs)
        Rails.cache.delete("agents/ordered")
        Rails.logger.info("[TelegramWebhook] #{full_name} → #{status}#{task ? " (#{task})" : ""}")
      end

      def extract_task(text)
        # Try to extract a meaningful task description from the message
        if text =~ /security\s+scan/i
          "Security scanning"
        elsif text =~ /scanning\s+(\w+)/i
          "Scanning #{$1}"
        elsif text =~ /checking\s+(.+?)(?:\.|,|$)/i
          "Checking #{$1.strip}"
        elsif text =~ /running\s+(.+?)(?:\.|,|$)/i
          "Running #{$1.strip}"
        else
          text.truncate(80)
        end
      end
    end
  end
end

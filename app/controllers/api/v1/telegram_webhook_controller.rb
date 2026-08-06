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
        from_user = params.dig(:message, :from, :first_name)

        Rails.logger.info("[TelegramWebhook] from=#{from_user} bot=#{bot_reply} text=#{message_text.truncate(80).inspect}")

        # Check for human user commands
        if !bot_reply && message_text.present?
          if smoke_request?(message_text)
            handle_smoke_request(from_user)
            head :ok
            return
          elsif deploy_request?(message_text)
            handle_deploy_request(message_text, from_user)
            head :ok
            return
          end
        end

        # Only process bot messages (from our agent bot)
        if bot_reply && message_text.present?
          detect_agent_status(message_text)
        end

        head :ok
      end

      private

      # Legacy fallback only. Agents are resolved from the database by slug
      # (see #find_agent) so anyone added later via /admin/agents checks in
      # too; this map stays for agents whose slug drifted from their name.
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
        agent = find_agent(name_fragment)
        return unless agent

        attrs = { status: status, last_active_at: Time.current }
        attrs[:current_task] = task if status == "busy" || status == "error"
        attrs[:current_task] = nil if status == "online"

        agent.update!(attrs)
        Rails.cache.delete("agents/ordered")
        Rails.logger.info("[TelegramWebhook] #{agent.name} → #{status}#{task ? " (#{task})" : ""}")
      end

      # Match the word the bot used against an agent's slug, which Agent
      # derives from the first word of its name minus the emoji ("Knox 🔒" ->
      # "knox"). Reading the roster from the database means an agent added
      # after the original seven still reports in; previously the hardcoded
      # map silently dropped their updates and they looked idle forever.
      def find_agent(name_fragment)
        key = name_fragment.to_s.downcase.strip
        return if key.blank?

        Agent.find_by(slug: key) || (AGENT_NAMES[key] && Agent.find_by(name: AGENT_NAMES[key]))
      end

      DEPLOY_PATTERNS = [
        /(?:knox|claude)[\s,]*deploy\s+(\S+)/i,
        /deploy\s+(?:the\s+)?(\S+?)(?:\s+app)?(?:\s+for\s+me)?$/i,
        /(?:push|ship|release)\s+(\S+)\s+(?:to\s+)?prod/i
      ].freeze

      APP_ALIASES = {
        "agent44" => "agent44-app",
        "agent44_app" => "agent44-app",
        "agent44-app" => "agent44-app",
        "openclaw" => "agent44-app",
        "app" => "agent44-app"
      }.freeze

      def deploy_request?(text)
        DEPLOY_PATTERNS.any? { |p| text.match?(p) }
      end

      def handle_deploy_request(text, from_user)
        app = "agent44-app"
        DEPLOY_PATTERNS.each do |pattern|
          if (match = text.match(pattern))
            app = APP_ALIASES[match[1].downcase.strip] || match[1].strip
            break
          end
        end

        message = AgentMessage.create!(
          role: "user",
          agent: "Knox \u{1f512}",
          content: "deploy:#{app}",
          status: "pending"
        )

        knox = Agent.find_by(name: "Knox \u{1f512}")
        knox&.update!(status: "busy", current_task: "Deploying #{app}", last_active_at: Time.current)
        Rails.cache.delete("agents/ordered")

        Notification.notify!(
          level: "info",
          source: "deploy",
          title: "Deploy requested",
          body: "#{from_user} requested deploy of #{app} via Telegram",
          telegram: true
        )

        Rails.logger.info("[TelegramWebhook] Deploy queued: #{app} by #{from_user}")
      end

      def smoke_request?(text)
        text.match?(%r{^/smoke_nyk(?:@\S+)?$}i)
      end

      def handle_smoke_request(from_user)
        SmokeDispatch.trigger!(requested_by: from_user, via: "Telegram")
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

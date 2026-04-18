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

      DEPLOY_PATTERNS = [
        /(?:knox|claude)[\s,]*deploy\s+(\S+)/i,
        /deploy\s+(?:the\s+)?(\S+?)(?:\s+app)?(?:\s+for\s+me)?$/i,
        /(?:push|ship|release)\s+(\S+)\s+(?:to\s+)?prod/i,
      ].freeze

      APP_ALIASES = {
        "agent44" => "agent44-app",
        "agent44_app" => "agent44-app",
        "agent44-app" => "agent44-app",
        "openclaw" => "agent44-app",
        "app" => "agent44-app",
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
        text.match?(%r{^/smoke(?:@\S+)?$}i)
      end

      def handle_smoke_request(from_user)
        token = ENV["GITHUB_PAT"]
        if token.blank?
          Rails.logger.warn("[TelegramWebhook] GITHUB_PAT not set — cannot trigger smoke workflow")
          return
        end

        uri = URI("https://api.github.com/repos/agent44bot/agent44_app/dispatches")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 10

        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{token}"
        req["Accept"] = "application/vnd.github+json"
        req["Content-Type"] = "application/json"
        req.body = { event_type: "smoke-nyk" }.to_json

        res = http.request(req)

        if res.is_a?(Net::HTTPSuccess) || res.code == "204"
          Notification.notify!(
            level: "info",
            source: "smoke_test",
            title: "Smoke test triggered",
            body: "#{from_user} requested NY Kitchen smoke test via Telegram",
            telegram: true
          )
          Rails.logger.info("[TelegramWebhook] Smoke test triggered by #{from_user}")
        else
          Rails.logger.error("[TelegramWebhook] GitHub dispatch failed (#{res.code}): #{res.body.to_s[0, 200]}")
        end
      rescue => e
        Rails.logger.error("[TelegramWebhook] Smoke trigger error: #{e.class}: #{e.message}")
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

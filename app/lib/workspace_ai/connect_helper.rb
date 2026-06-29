# Answers a workspace member's questions about connecting (and posting to) a
# given social platform, using Claude Haiku. Grounded in the real, current
# connect steps + this workspace's connection status so it does not invent
# flows for platforms that are not live yet. Usage is logged through the same
# AiCallLogger as the Drafter, scoped to the workspace + user, so the cost
# rolls up on the workspace's billing.
module WorkspaceAi
  class ConnectHelper
    MODEL      = "claude-haiku-4-5-20251001"
    SOURCE     = "connect_help_chat"
    MAX_TOKENS = 350
    MAX_TURNS  = 8        # cap history we send back (keeps each reply cheap)
    MAX_MSG    = 1_000    # clamp any single message we forward to the model

    Result = Struct.new(:ok?, :reply, :error, :cost_dollars, keyword_init: true)

    # Per-platform facts the model is allowed to rely on. Availability is honest:
    # X + Bluesky post live today; the Meta platforms need setup we may not have
    # finished, so the helper says so instead of promising a flow that dead-ends.
    PLATFORM_FACTS = {
      "x" => "X (Twitter): Connecting is one click. Press Connect, log in to X, and authorize Agent44 Labs. You come right back connected. This is fully available.",
      "bluesky" => "Bluesky: Uses an app password, not your main password. In the Bluesky app go to Settings, then App Passwords, and create one. Then press Connect here and enter your handle plus that app password. This is fully available.",
      "threads" => "Threads: Connects through Meta with your Threads (Instagram) account. Press Connect, log in through Meta, and approve access. Note: Threads may not be switched on for this workspace yet while the Agent44 team finishes Meta setup. If Connect does not work, that is why, and they should reach out to the Agent44 team rather than keep retrying.",
      "facebook" => "Facebook: Connects through Meta. You log in with Facebook and pick the Page you post from (you must have a Facebook Page, a personal profile is not enough). Note: Facebook may not be switched on for this workspace yet while the Agent44 team finishes Meta setup. If Connect does not work, that is why.",
      "instagram" => "Instagram: Connects through Meta, the same login as Facebook. Your Instagram must be a Professional (Business or Creator) account linked to a Facebook Page. Note: Instagram is not switched on yet while the Agent44 team finishes Meta setup."
    }.freeze

    # Swap with a Proc(system:, messages:) -> response in tests so we never hit
    # the real API (same approach as Drafter.stub).
    class << self
      attr_accessor :stub
    end

    def initialize(workspace, user: nil)
      @workspace = workspace
      @user      = user
    end

    # platform: one of PLATFORM_FACTS keys. message: the new user message.
    # history: array of { "role" => "user"|"assistant", "content" => "..." }.
    def answer(platform:, message:, history: [])
      api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
      return Result.new(ok?: false, error: "ANTHROPIC_API_KEY not set") if api_key.blank?
      return Result.new(ok?: false, error: "Message is blank") if message.to_s.strip.blank?

      messages = build_messages(history, message)
      system   = system_prompt(platform)

      response =
        if self.class.stub
          self.class.stub.call(system: system, messages: messages)
        else
          client = Anthropic::Client.new(api_key: api_key)
          client.messages.create(model: MODEL, max_tokens: MAX_TOKENS, system: system, messages: messages)
        end

      log  = AiCallLogger.log!(response, model: MODEL, source: SOURCE, user: @user, workspace: @workspace)
      text = extract_text(response)
      return Result.new(ok?: false, error: "Empty AI response") if text.blank?

      Result.new(ok?: true, reply: text.strip, cost_dollars: log&.cost_dollars.to_f)
    rescue Anthropic::Errors::APIError => e
      Result.new(ok?: false, error: "Anthropic: #{e.message}")
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    private

    def build_messages(history, message)
      turns = Array(history).last(MAX_TURNS).filter_map do |m|
        role    = (m["role"] || m[:role]).to_s
        content = (m["content"] || m[:content]).to_s.strip
        next if content.blank? || !%w[user assistant].include?(role)
        { role: role, content: content[0, MAX_MSG] }
      end
      turns + [ { role: "user", content: message.to_s.strip[0, MAX_MSG] } ]
    end

    def system_prompt(platform)
      key       = platform.to_s
      label     = key.capitalize
      facts     = PLATFORM_FACTS[key] || "This platform is not one of the supported options."
      connected = @workspace.social_accounts.where(platform: key, status: "active").exists?
      status    = connected ? "It is currently CONNECTED for this workspace." : "It is currently NOT connected for this workspace."

      <<~PROMPT
        You are the connection helper for #{@workspace.name} inside Agent44 Labs' Social Agent.
        Help this user connect and post to their social platforms. Right now they are asking about #{label}.

        Facts about #{label} you must rely on (do not contradict or invent beyond these):
        #{facts}
        #{status}

        Rules:
        - Stay on the topic of connecting to or posting on social platforms. If asked something off topic, gently steer back.
        - Be brief and friendly. Short steps or a short paragraph. No em-dashes.
        - Never invent steps or claim a platform works if the facts above say it may not be available. Be honest.
        - If you cannot resolve their issue, suggest they reach out to the Agent44 team.
        - Do not ask for or accept passwords in chat. For Bluesky, point them to the Connect button to enter their app password securely.
      PROMPT
    end

    def extract_text(response)
      if response.respond_to?(:content)
        response.content.first&.text
      elsif response.is_a?(Hash)
        response.dig(:content, 0, :text) || response.dig("content", 0, "text")
      end
    end
  end
end

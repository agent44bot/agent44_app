# frozen_string_literal: true

# SKETCH — not wired to any controller/route yet. See docs/agentic-super-agent.md.
#
# The agentic successor to KitchenAi::AskAgent. Where AskAgent pre-stuffs the
# snapshot into the system prompt and answers in one shot, AgenticAgent exposes
# tools and runs a loop: call Claude → if it asked for tools, run them and feed
# results back → repeat until end_turn. Read tools let it pull data on demand;
# write tools let it act on the fleet (gated by workspace role + audited).
#
# Design rationale, the authorization decision, and rollout: docs/agentic-super-agent.md.
module KitchenAi
  class AgenticAgent
    MODEL      = "claude-haiku-4-5"   # see docs §Model + cost for the Sonnet upgrade path
    SOURCE     = "nyk_agent"
    MAX_TOKENS = 1024
    MAX_STEPS  = 6                    # hard cap so a confused model can't spin forever

    # Frozen — NO date, snapshot, or fleet status here (those would bust the
    # prompt cache every call). The agent pulls live data via read tools.
    SYSTEM_PROMPT = <<~PROMPT
      You are Super Agent for New York Kitchen, a culinary education center in
      Canandaigua, NY. You help Lora and her team. You sit on top of a fleet of
      agents (List, Data, Test, Display, Social) and can both answer questions
      and take actions on the fleet using the tools provided.

      Rules:
      - Use read tools to ground every factual claim; never invent classes,
        prices, seat counts, or test results.
      - Prefer the smallest action that answers the request. Don't trigger a
        scrape or smoke test unless asked or clearly warranted.
      - Times are Eastern; prices USD. Be concise.
    PROMPT

    Result = Struct.new(:ok?, :reply, :steps, :actions, :error, keyword_init: true)

    class << self
      attr_accessor :stub   # Proc(model:, max_tokens:, system:, messages:, tools:) -> response. Tests set this; never hits the API.
    end

    # workspace_role gates which tools exist and whether write tools may run.
    def initialize(user:, workspace_role: nil)
      @user           = user
      @workspace_role = workspace_role.to_s
      @actions_taken  = []
    end

    # messages: [{role:, content:}] — same shape AskAgent accepts.
    def run(messages)
      api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
      return Result.new(ok?: false, error: "ANTHROPIC_API_KEY not set") if api_key.blank?

      client   = self.class.stub ? nil : Anthropic::Client.new(api_key: api_key)
      convo    = sanitize(messages)
      return Result.new(ok?: false, error: "No message") if convo.empty?

      tools = tool_definitions
      steps = 0

      loop do
        steps += 1
        return Result.new(ok?: false, error: "Step limit reached", steps: steps) if steps > MAX_STEPS

        response = create_message(client, system: cached_system, messages: convo, tools: tools)
        AiCallLogger.log!(response, model: MODEL, source: SOURCE, user: @user)

        # Always append the assistant's full content — tool_use blocks must be
        # preserved for the matching tool_result on the next turn.
        convo << { role: "assistant", content: assistant_content(response) }

        if stop_reason(response) == "tool_use"
          tool_uses = content_blocks(response).select { |b| block_type(b) == "tool_use" }
          convo << { role: "user", content: tool_uses.map { |tu| run_tool(tu) } }
          next
        end

        return Result.new(ok?: true, reply: extract_text(response), steps: steps, actions: @actions_taken)
      end
    rescue Anthropic::Errors::APIError => e
      Result.new(ok?: false, error: "Anthropic: #{e.message}", steps: steps, actions: @actions_taken)
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}", steps: steps, actions: @actions_taken)
    end

    private

    def admin? = %w[owner admin].include?(@workspace_role)

    # System prompt as a cacheable block. cache_control on the last (only) block
    # caches tools + system together (render order: tools → system → messages).
    def cached_system
      [ { type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } } ]
    end

    def create_message(client, system:, messages:, tools:)
      args = { model: MODEL, max_tokens: MAX_TOKENS, system: system, messages: messages, tools: tools }
      return self.class.stub.call(**args) if self.class.stub
      client.messages.create(**args)
    end

    # --- Tool registry -----------------------------------------------------
    # Read tools always available; write tools only for owner/admin (tool_choice
    # allowlist by role, per docs §authorization option 3). The last def carries
    # the cache breakpoint so the tools prefix caches.
    def tool_definitions
      defs = READ_TOOLS.dup
      defs += WRITE_TOOLS if admin?
      defs.each_with_index.map do |d, i|
        d = d.dup
        d[:cache_control] = { type: "ephemeral" } if i == defs.size - 1
        d
      end
    end

    READ_TOOLS = [
      { name: "get_fleet_status",
        description: "Current status of every NYK agent (List, Data, Test, Display, Social): counts, last run times, failures.",
        input_schema: { type: "object", properties: {}, additionalProperties: false } },
      { name: "list_classes",
        description: "Upcoming NYK classes from the latest snapshot. Use to answer what's on the calendar / what sold out.",
        input_schema: { type: "object",
                        properties: { filter: { type: "string", enum: %w[upcoming sold_out all] } },
                        additionalProperties: false } },
      { name: "get_sales_summary",
        description: "Rolling ticket-sales numbers: avg/day over 14 days, sold so far today and this week.",
        input_schema: { type: "object", properties: {}, additionalProperties: false } },
    ].freeze

    WRITE_TOOLS = [
      { name: "trigger_scrape",
        description: "Run the Data Agent now to refresh the class snapshot. Reversible (just refreshes data).",
        input_schema: { type: "object", properties: {}, additionalProperties: false } },
      { name: "trigger_smoke_test",
        description: "Run the Test Agent's smoke check now. Read-only verification, fire-and-forget.",
        input_schema: { type: "object",
                        properties: { test: { type: "string", enum: %w[nav scrape all] } },
                        additionalProperties: false } },
      { name: "draft_social_post",
        description: "Draft a social post about a topic. Creates a DRAFT only — never publishes.",
        input_schema: { type: "object",
                        properties: { topic: { type: "string", description: "What the post should be about" } },
                        required: %w[topic], additionalProperties: false } },
    ].freeze

    # --- Tool dispatch -----------------------------------------------------
    def run_tool(tool_use)
      name  = block_name(tool_use)
      input = (block_input(tool_use) || {})
      input = input.is_a?(Hash) ? input.with_indifferent_access : {}
      text, is_error = execute(name, input)
      { type: "tool_result", tool_use_id: block_id(tool_use), content: text.to_s, is_error: !!is_error }
    rescue => e
      { type: "tool_result", tool_use_id: block_id(tool_use), content: "Tool error: #{e.message}", is_error: true }
    end

    def execute(name, input)
      case name
      when "get_fleet_status"  then [ fleet_status_text, false ]
      when "list_classes"      then [ list_classes_text(input[:filter] || "upcoming"), false ]
      when "get_sales_summary" then [ sales_summary_text, false ]
      when "trigger_scrape", "trigger_smoke_test", "draft_social_post"
        return [ "Not allowed: this action requires workspace owner/admin.", true ] unless admin?
        write_action(name, input)
      else
        [ "Unknown tool: #{name}", true ]
      end
    end

    # Write handlers. Each records an audit entry in @actions_taken; a real
    # build would persist (see docs open question on AgentActionLog).
    def write_action(name, input)
      case name
      when "trigger_scrape"
        ScrapeKitchenJob.perform_later
        record(name, {})
        [ "Scrape queued. The snapshot will refresh shortly.", false ]
      when "trigger_smoke_test"
        test = %w[nav scrape all].include?(input[:test]) ? input[:test] : "all"
        # TODO: extract Api::V1::TelegramWebhookController#handle_smoke_request into
        # a Nyk::SmokeDispatcher service and call it here (GitHub repository_dispatch).
        record(name, { test: test })
        [ "Smoke test (#{test}) triggered. Check the hub for the result.", false ]
      when "draft_social_post"
        ws = Workspace.find_by(slug: "nykitchen")
        res = WorkspaceAi::Drafter.new(ws, user: @user).suggest(topic: input[:topic])
        return [ "Couldn't draft: #{res.error}", true ] unless res.ok?
        # TODO: persist as a WorkspaceDraft (status: draft) rather than just returning text.
        record(name, { topic: input[:topic] })
        [ "Drafted (NOT posted):\n#{res.text}", false ]
      end
    end

    def record(action, args) = @actions_taken << { action: action, args: args, at: Time.current }

    # --- Read-tool data (thin wrappers; reuse AskAgent's computations) ------
    # NOTE: extract format_fleet_status / format_events out of AskAgent into a
    # shared module so both agents read identical numbers. Stubbed here.
    def fleet_status_text  = KitchenAi::AskAgent.new(user: @user).send(:format_fleet_status)
    def sales_summary_text
      avg = KitchenSnapshot.tickets_sold_daily_avg
      wk  = KitchenSnapshot.tickets_sold_this_week_by_wday.values.compact.sum.to_i
      "Avg tickets/day (14d): #{avg || 'n/a'}\nSold this week: #{wk}"
    end

    def list_classes_text(filter)
      snap = KitchenSnapshot.latest
      return "No snapshot yet." unless snap
      events = snap.kitchen_events.upcoming.order(:start_at)
      events = events.reject(&:sold_out?) if filter == "upcoming"
      events = events.select(&:sold_out?) if filter == "sold_out"
      events.first(50).map { |e|
        d = e.start_at&.in_time_zone("Eastern Time (US & Canada)")&.strftime("%a %b %-d %-l:%M%P")
        "#{d} · #{e.name} · #{e.sold_out? ? 'SOLD OUT' : "#{e.spots_left} left"}"
      }.join("\n").presence || "No matching classes."
    end

    # --- SDK shape helpers (tolerate both SDK objects and stub hashes) ------
    def content_blocks(r)   = r.respond_to?(:content) ? r.content : (r[:content] || r["content"] || [])
    def stop_reason(r)      = r.respond_to?(:stop_reason) ? r.stop_reason.to_s : (r[:stop_reason] || r["stop_reason"]).to_s
    def block_type(b)       = (b.respond_to?(:type) ? b.type : (b[:type] || b["type"])).to_s
    def block_name(b)       = b.respond_to?(:name)  ? b.name  : (b[:name]  || b["name"])
    def block_id(b)         = b.respond_to?(:id)    ? b.id    : (b[:id]    || b["id"])
    def block_input(b)      = b.respond_to?(:input) ? b.input : (b[:input] || b["input"])

    # Pass the assistant turn back verbatim so tool_use blocks survive the round trip.
    def assistant_content(r) = content_blocks(r)

    def extract_text(r)
      content_blocks(r).filter_map { |b| (b.respond_to?(:text) ? b.text : (b[:text] || b["text"])) if block_type(b) == "text" }
                       .join("\n").strip
    end

    def sanitize(messages)
      Array(messages).filter_map do |m|
        m = m.with_indifferent_access if m.is_a?(Hash)
        role = m[:role].to_s
        content = m[:content]
        next unless %w[user assistant].include?(role)
        next if content.blank?
        { role: role, content: content }
      end.last(30)
    end
  end
end

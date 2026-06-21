class AiCallLog < ApplicationRecord
  belongs_to :user, optional: true

  # Per-model published rates in $/MTok at write time. Update here when
  # Anthropic changes pricing — historical rows then reflect the new rate
  # which is fine for our trial billing. If we ever need rate-as-of, snapshot
  # the rate onto the row at create time instead.
  RATES = {
    "claude-haiku-4-5-20251001" => { input: 1.00, output:  5.00 },
    "claude-sonnet-4-6"         => { input: 3.00, output: 15.00 },
    "claude-opus-4-8"           => { input: 5.00, output: 25.00 }
  }.freeze
  DEFAULT_RATE = { input: 1.00, output: 5.00 }.freeze

  # Customer-billable NYK features. nyk_grocery_list + nyk_recipe_extract are
  # Opus, not Haiku; cost_dollars/total_cost_dollars price them correctly via
  # RATES, but keep them out of any Haiku-flat usage_rollup. nyk_ask is the
  # customer-facing Super Agent chat (Lora's team). We deliberately do NOT bill
  # nyk_agent: it's the admin-only read-only AgenticAgent we run to dogfood, so
  # it's our cost, not the customer's.
  NYK_SOURCES = %w[nyk_enhance nyk_x_autopost nyk_team_report nyk_recipe_extract nyk_receipt_extract nyk_grocery_list nyk_ask].freeze
  # The two Opus "kitchen prep" features (Sam the List agent): the consolidated
  # grocery list and recipe extraction. Both bill at the Opus rate.
  LIST_AGENT_SOURCES = %w[nyk_grocery_list nyk_recipe_extract].freeze
  # The /nykitchen/ask Super Agent chat: nyk_ask is the single-shot AskAgent
  # (what customers like Lora get), nyk_agent is the read-only AgenticAgent
  # (admin dogfood). Both are Haiku 4.5, so usage_rollup's flat-rate cost holds.
  # Used for the hub "ask" salary badge (internal view, shows both).
  SUPER_AGENT_SOURCES = %w[nyk_ask nyk_agent].freeze

  scope :nyk,         -> { where(source: NYK_SOURCES) }
  scope :super_agent, -> { where(source: SUPER_AGENT_SOURCES) }
  scope :this_month,  -> { where("created_at >= ?", Time.zone.now.beginning_of_month) }

  def cost_dollars
    rate = RATES[model] || DEFAULT_RATE
    input_dollars  = input_tokens  * rate[:input]  / 1_000_000.0
    output_dollars = output_tokens * rate[:output] / 1_000_000.0
    input_dollars + output_dollars
  end

  def cost_cents
    cost_dollars * 100
  end

  def self.total_cost_dollars(scope = all)
    scope.to_a.sum(&:cost_dollars)
  end

  # Aggregate calls/tokens/cost for a scope in a single SQL query (no per-row
  # object loading). Cost uses the flat DEFAULT_RATE, which is exact for any
  # all-Haiku-4.5 scope (e.g. super_agent). Don't use for mixed-model scopes.
  def self.usage_rollup(scope = all)
    calls, inp, out = scope.pick(
      Arel.sql("COUNT(*), COALESCE(SUM(input_tokens), 0), COALESCE(SUM(output_tokens), 0)")
    )
    inp = inp.to_i
    out = out.to_i
    {
      calls:         calls.to_i,
      input_tokens:  inp,
      output_tokens: out,
      total_tokens:  inp + out,
      cost_dollars:  (inp * DEFAULT_RATE[:input] + out * DEFAULT_RATE[:output]) / 1_000_000.0
    }
  end

  def self.summary_by_source(scope = all)
    scope.group_by(&:source).transform_values do |logs|
      {
        calls:          logs.size,
        input_tokens:   logs.sum(&:input_tokens),
        output_tokens:  logs.sum(&:output_tokens),
        cost_dollars:   logs.sum(&:cost_dollars)
      }
    end
  end

  # Short, human label for an Anthropic model id ("claude-opus-4-8" -> "Opus").
  def self.model_label(model)
    case model.to_s
    when /opus/i   then "Opus"
    when /haiku/i  then "Haiku"
    when /sonnet/i then "Sonnet"
    else model.to_s.presence || "Unknown"
    end
  end

  # Per-model calls + cost for a scope, keyed by friendly label (Opus, Haiku),
  # so billing can show spend per Anthropic model alongside the per-feature view.
  def self.summary_by_model(scope = all)
    scope.group_by { |l| model_label(l.model) }.transform_values do |logs|
      {
        calls:         logs.size,
        input_tokens:  logs.sum(&:input_tokens),
        output_tokens: logs.sum(&:output_tokens),
        cost_dollars:  logs.sum(&:cost_dollars)
      }
    end
  end

  EMPTY_USAGE = { calls: 0, input_tokens: 0, output_tokens: 0, cost_dollars: 0.0 }.freeze

  # Per-calendar-month usage for the given sources over the last `months`
  # months (workspace-local tz via Time.zone), for the AI spend page. Buckets
  # are computed in Ruby per month so boundaries respect the app time zone (vs
  # grouping on a UTC SQL date). Cost is per-row (RATES per model), so this is
  # correct even if a source's model changes. Oldest month first; every source
  # appears in every month (zero-filled) so the view can render flat bars.
  #
  #   [ { key: "2026-06", label: "Jun", start: <Date>,
  #       by_source: { "nyk_grocery_list" => {calls:, cost_dollars:, ...}, ... },
  #       cost_dollars: <month total across the sources> }, ... ]
  def self.monthly_by_source(sources, months: 6, now: Time.zone.now)
    # One query for the whole window, then bucket by month in Ruby (cost is
    # per-row, RATES per model, so it can't be a pure SQL aggregate anyway).
    window_start = now.beginning_of_month - (months - 1).months
    logs = where(source: sources, created_at: window_start..).to_a
    by_month = logs.group_by { |l| l.created_at.in_time_zone(now.time_zone).strftime("%Y-%m") }

    (0...months).map do |i|
      month_start = now.beginning_of_month - i.months
      found       = summary_by_source(by_month[month_start.strftime("%Y-%m")] || [])
      by_source   = sources.index_with { |s| found[s] || EMPTY_USAGE }
      {
        key:          month_start.strftime("%Y-%m"),
        label:        month_start.strftime("%b"),
        start:        month_start.to_date,
        by_source:    by_source,
        cost_dollars: by_source.values.sum { |h| h[:cost_dollars] }
      }
    end.reverse
  end
end

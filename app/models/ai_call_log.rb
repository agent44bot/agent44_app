class AiCallLog < ApplicationRecord
  belongs_to :user, optional: true

  # Per-model published rates in $/MTok at write time. Update here when
  # Anthropic changes pricing — historical rows then reflect the new rate
  # which is fine for our trial billing. If we ever need rate-as-of, snapshot
  # the rate onto the row at create time instead.
  RATES = {
    "claude-haiku-4-5-20251001" => { input: 1.00, output: 5.00 },
    "claude-opus-4-8"           => { input: 5.00, output: 25.00 }
  }.freeze
  DEFAULT_RATE = { input: 1.00, output: 5.00 }.freeze

  # nyk_recipe_extract is Opus, not Haiku; cost_dollars/total_cost_dollars
  # price it correctly via RATES, but keep it out of any Haiku-flat usage_rollup.
  NYK_SOURCES = %w[nyk_enhance nyk_x_autopost nyk_team_report nyk_recipe_extract nyk_receipt_extract].freeze
  # The /nykitchen/ask Super Agent chat: nyk_ask is the single-shot AskAgent
  # (what customers like Lora get), nyk_agent is the read-only AgenticAgent
  # (admin dogfood). Both are Haiku 4.5, so usage_rollup's flat-rate cost holds.
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
    (0...months).map do |i|
      month_start = now.beginning_of_month - i.months
      found       = summary_by_source(where(source: sources, created_at: month_start...(month_start + 1.month)))
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

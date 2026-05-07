class AiCallLog < ApplicationRecord
  belongs_to :user, optional: true

  # Per-model published rates in $/MTok at write time. Update here when
  # Anthropic changes pricing — historical rows then reflect the new rate
  # which is fine for our trial billing. If we ever need rate-as-of, snapshot
  # the rate onto the row at create time instead.
  RATES = {
    "claude-haiku-4-5-20251001" => { input: 1.00, output: 5.00 }
  }.freeze
  DEFAULT_RATE = { input: 1.00, output: 5.00 }.freeze

  NYK_SOURCES = %w[nyk_enhance nyk_x_autopost].freeze

  scope :nyk,        -> { where(source: NYK_SOURCES) }
  scope :this_month, -> { where("created_at >= ?", Time.zone.now.beginning_of_month) }

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
end

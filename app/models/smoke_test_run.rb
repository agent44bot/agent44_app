class SmokeTestRun < ApplicationRecord
  # "running" rows are created when a smoke/scrape kicks off and patched
  # to passed/failed when it finishes. Lets the hub show actual in-flight
  # state (pulsing dot) instead of guessing from started_at age.
  STATUSES = %w[running passed failed].freeze
  COST_PER_MINUTE = 0.00044 # $0.00044/min

  has_one_attached :video
  has_one_attached :thumbnail
  has_one_attached :page_source
  has_one_attached :trace

  validates :name, :status, :started_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  before_save :compute_cost, if: :duration_ms

  scope :recent, -> { order(started_at: :desc) }
  scope :for_name, ->(n) { where(name: n) }
  scope :nyk_nav,    -> { where("smoke_test_runs.name LIKE 'nyk_calendar_nav%'") }
  scope :nyk_scrape, -> { where("smoke_test_runs.name LIKE 'nyk_scrape%'") }
  scope :nyk, -> { where("smoke_test_runs.name LIKE 'nyk_calendar_nav%' OR smoke_test_runs.name LIKE 'nyk_scrape%'") }

  def passed?
    status == "passed"
  end

  def failed?
    status == "failed"
  end

  def running?
    status == "running"
  end

  scope :finished, -> { where.not(status: "running") }

  # Number of consecutive most-recent finished nav runs that failed. Drives the
  # "failing repeatedly" escalation (see KitchenAi::SmokeEscalation). Nav = the
  # calendar round-trip — the customer-facing "is the site broken" check.
  def self.nyk_nav_failure_streak(lookback: 20)
    nyk_nav.finished.order(started_at: :desc).limit(lookback).to_a
           .take_while(&:failed?).size
  end

  # started_at of the first failure in the current nav streak (the incident's
  # start), or nil if the most recent finished nav run passed.
  def self.nyk_nav_streak_started_at(lookback: 20)
    nyk_nav.finished.order(started_at: :desc).limit(lookback).to_a
           .take_while(&:failed?).last&.started_at
  end

  def kind
    name.to_s.start_with?("nyk_scrape") ? "scrape" : "nav"
  end

  # Friendly duration string for display
  def duration_label
    return "—" unless duration_ms
    secs = duration_ms / 1000.0
    secs < 60 ? "#{secs.round(1)}s" : "#{(secs / 60).round(1)}m"
  end

  # Pass/fail rollup for a named scope (:nyk_nav / :nyk_scrape) over a date
  # window — powers the Test (Argus) and Data (Scout) weekly briefs.
  # { total:, passed:, failed:, fail_pct: }.
  def self.window_stats(scope_name, from, to)
    rel    = public_send(scope_name).finished.where(started_at: from.beginning_of_day..to.end_of_day)
    total  = rel.count
    failed = rel.where(status: "failed").count
    { total: total, passed: total - failed, failed: failed,
      fail_pct: total.positive? ? (100.0 * failed / total).round : 0 }
  end

  private

  def compute_cost
    minutes = duration_ms / 60_000.0
    self.cost_dollars = (minutes * COST_PER_MINUTE).round(6)
  end
end

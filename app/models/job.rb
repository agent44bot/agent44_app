class Job < ApplicationRecord
  CATEGORIES = %w[full_time part_time contract].freeze
  ROLE_CLASSES = %w[traditional ai_augmented agent_director].freeze
  BITCOIN_SOURCES = %w[bitcoinjobs bitcoinerjobs bitcoin_bamboohr].freeze

  # Security/crypto silo keyword patterns (used on /crypto page)
  SECURITY_ENGINEER_PATTERN = /\b(security engineer|appsec|application security|pentesting|penetration testing|cryptograph|zero trust|smart contract audit|blockchain security|web3 security|identity engineer|security architect|infosec|vulnerability|threat model|security testing)\b/i
  CRYPTO_TRUSTLESS_PATTERN  = /\b(bitcoin|lightning network|nostr|blockchain|decentralized|web3|smart contract|solidity|cryptographic|key management|zero knowledge|zk-proof|trustless|consensus|distributed ledger|wallet|signing|schnorr|elliptic curve)\b/i
  SECURITY_FIRST_PATTERN    = /\b(devsecops|shift.left security|sast|dast|sbom|supply chain security|compliance.as.code|security automation|passkey|webauthn|fido2|oauth|oidc|identity.access|iam|secrets management|vault|security scan|dependency audit)\b/i

  scope :security_engineer, -> {
    where("title LIKE '%security%' OR title LIKE '%appsec%' OR title LIKE '%pentest%' OR title LIKE '%cryptograph%' OR title LIKE '%infosec%' OR title LIKE '%zero trust%'")
  }
  scope :crypto_trustless, -> {
    where("title LIKE '%bitcoin%' OR title LIKE '%blockchain%' OR title LIKE '%web3%' OR title LIKE '%crypto%' OR title LIKE '%nostr%' OR title LIKE '%decentralized%' OR description LIKE '%smart contract%' OR description LIKE '%zero knowledge%'")
  }
  scope :security_first, -> {
    where("title LIKE '%devsecops%' OR title LIKE '%security automation%' OR title LIKE '%appsec%' OR description LIKE '%shift left%' OR description LIKE '%sast%' OR description LIKE '%dast%' OR description LIKE '%passkey%' OR description LIKE '%webauthn%' OR description LIKE '%supply chain security%'")
  }

  has_many :job_sources, dependent: :destroy

  validates :title, :url, :category, presence: true
  validates :url, uniqueness: { scope: :source }
  validates :category, inclusion: { in: CATEGORIES }

  before_validation :set_normalized_fields

  scope :active, -> { where(active: true) }
  scope :by_category, ->(cat) { where(category: cat) if cat.present? }
  # Note: ai_augmented scope is the legacy "any AI flavor" view (includes
  # agent_director). Use the role_class scopes for the strict, mutually
  # exclusive split.
  scope :ai_augmented, -> { where(ai_augmented: true) }
  scope :traditional, -> { where(role_class: "traditional") }
  scope :ai_augmented_only, -> { where(role_class: "ai_augmented") }
  scope :agent_director, -> { where(role_class: "agent_director") }
  scope :by_role_class, ->(rc) { where(role_class: rc) if rc.present? }
  scope :by_source, ->(src) {
    joins(:job_sources).where(job_sources: { source: src }).distinct if src.present?
  }
  scope :recent, -> { order(created_at: :desc) }
  scope :search, ->(q) {
    left_joins(:job_sources)
      .where("jobs.title LIKE ? OR jobs.company LIKE ? OR jobs.location LIKE ? OR job_sources.source LIKE ?", "%#{q}%", "%#{q}%", "%#{q}%", "%#{q}%")
      .distinct if q.present?
  }
  scope :posted_today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :remote, -> { where("location LIKE ? OR location LIKE ? OR title LIKE ?", "%Remote%", "%Anywhere%", "%Remote%") }
  scope :by_skill, ->(skill) {
    next all if skill.blank?
    pattern = SkillExtractor::PATTERNS[skill]
    next none unless pattern
    # SQLite REGEXP isn't enabled by default; do a coarse LIKE prefilter then
    # an in-Ruby regex filter to get exact word-boundary matches.
    likes = SkillExtractor::SKILLS[skill].map { |v| "%#{v.gsub(/\\\w|\\\b/, '').gsub('\\.', '.')}%" }
    cond = ([ "(description LIKE ? OR title LIKE ?)" ] * likes.size).join(" OR ")
    args = likes.flat_map { |l| [ l, l ] }
    candidates = where(cond, *args).pluck(:id, :title, :description)
    matching_ids = candidates.select { |_, t, d| "#{t} #{d}".match?(pattern) }.map(&:first)
    where(id: matching_ids)
  }
  scope :by_salary_desc, -> {
    order(Arel.sql("CASE WHEN salary IS NOT NULL AND salary != '' THEN 0 ELSE 1 END, CAST(REPLACE(REPLACE(SUBSTR(salary, 1, INSTR(salary || ' ', ' ') - 1), '$', ''), ',', '') AS REAL) DESC"))
  }
  scope :by_salary_asc, -> {
    order(Arel.sql("CASE WHEN salary IS NOT NULL AND salary != '' THEN 0 ELSE 1 END, CAST(REPLACE(REPLACE(SUBSTR(salary, 1, INSTR(salary || ' ', ' ') - 1), '$', ''), ',', '') AS REAL) ASC"))
  }

  def posted_today?
    created_at&.to_date == Time.current.to_date
  end

  def bitcoin_job?
    job_sources.any? { |js| BITCOIN_SOURCES.include?(js.source) }
  end

  def primary_source
    job_sources.min_by(&:created_at)
  end

  def multi_source?
    job_sources.size > 1
  end

  def source_names
    job_sources.map(&:source)
  end

  # Traditional vs AI-augmented split over a rolling window. Returns a hash with
  # raw counts, percentages, and the delta in AI percentage points vs the prior
  # window of equal length. Cached for 1 hour.
  def self.ai_demand_meter(window_days: 30)
    Rails.cache.fetch("jobs/ai_demand_meter/v3/#{window_days}", expires_in: 1.hour) do
      now = Time.current
      cur_start = now - window_days.days
      prev_start = now - (window_days * 2).days

      cur = active.where(posted_at: cur_start..now)
      cur_total = cur.count
      cur_director = cur.where(role_class: "agent_director").count
      cur_ai = cur.where(role_class: "ai_augmented").count
      cur_trad = cur_total - cur_ai - cur_director

      ai_pct = cur_total.zero? ? 0 : (cur_ai.to_f / cur_total * 100).round
      director_pct = cur_total.zero? ? 0 : (cur_director.to_f / cur_total * 100).round
      trad_pct = cur_total.zero? ? 0 : 100 - ai_pct - director_pct

      prev = active.where(posted_at: prev_start...cur_start)
      prev_total = prev.count
      prev_ai_combined = prev_total.zero? ? nil : prev.where(ai_augmented: true).count
      prev_ai_pct = prev_ai_combined.nil? ? nil : (prev_ai_combined.to_f / prev_total * 100).round
      cur_ai_combined_pct = cur_total.zero? ? 0 : ai_pct + director_pct
      delta = prev_ai_pct.nil? ? nil : (cur_ai_combined_pct - prev_ai_pct)

      prev_director_pct = prev_total.zero? ? nil : (prev.where(role_class: "agent_director").count.to_f / prev_total * 100).round
      director_delta = prev_director_pct.nil? ? nil : (director_pct - prev_director_pct)

      {
        traditional: cur_trad,
        ai: cur_ai,
        director: cur_director,
        total: cur_total,
        ai_pct: ai_pct,
        director_pct: director_pct,
        trad_pct: trad_pct,
        prev_ai_pct: prev_ai_pct,
        delta_pts: delta,
        prev_director_pct: prev_director_pct,
        director_delta_pts: director_delta,
        window_days: window_days
      }
    end
  end

  # Salary stats for a given role_class over the active job set. Parses the
  # leading dollar amount from the freeform `salary` string and reports
  # count, coverage, median, p25, p75. Cached 1h.
  def self.salary_stats(role_class:, window_days: 90)
    Rails.cache.fetch("jobs/salary_stats/v1/#{role_class}/#{window_days}", expires_in: 1.hour) do
      scope = active.where(role_class: role_class)
      scope = scope.where(posted_at: (Time.current - window_days.days)..Time.current) if window_days
      total = scope.count
      values = scope.where.not(salary: [ nil, "" ]).pluck(:salary).filter_map { |s| parse_salary_midpoint(s) }
      values.sort!
      n = values.size
      pct = ->(p) { n.zero? ? nil : values[((n - 1) * p).round] }
      {
        role_class: role_class,
        total: total,
        with_salary: n,
        coverage_pct: total.zero? ? 0 : (n.to_f / total * 100).round,
        median: pct.call(0.5),
        p25: pct.call(0.25),
        p75: pct.call(0.75),
        max: values.last,
        window_days: window_days
      }
    end
  end

  # Parses a freeform salary string like "$120,000 - $160,000", "85K–120K a year",
  # or "$150k" into the midpoint of the stated range (or the single value if no
  # range). Returns an integer dollar amount, or nil if:
  #   - it can't extract two-or-one annual figures
  #   - the string is hourly/daily/weekly/monthly
  #   - the resulting figure is outside [$20k, $1M] (sanity bounds)
  # Em-dash, en-dash, hyphen, and "to" are all treated as range separators.
  def self.parse_salary_midpoint(str)
    return nil if str.blank?
    s = str.to_s
    return nil if s.match?(/\b(hour|hr|hourly|day|daily|week|weekly|month|monthly)\b/i)

    s = s.gsub(",", "").gsub(/[—–]/, "-")
    nums = s.scan(/\$?\s*(\d+(?:\.\d+)?)\s*([kK])?/).filter_map { |digits, k|
      next nil if digits.empty?
      v = digits.to_f
      v *= 1000 if k.present?
      v.to_i
    }.select { |v| v >= 20_000 && v <= 1_000_000 }

    return nil if nums.empty?
    midpoint = nums.size >= 2 ? (nums[0] + nums[1]) / 2 : nums.first
    midpoint
  end

  # Top in-demand skills across active jobs, cached for 1 hour.
  # Returns [[name, count, percent], ...] sorted by count desc.
  def self.top_skills(limit: 10)
    Rails.cache.fetch("jobs/top_skills/v1/#{limit}", expires_in: 1.hour) do
      SkillExtractor.top_skills(active, limit: limit)
    end
  end

  def self.normalize_title(t)
    return nil if t.blank?
    t.downcase.strip
      .gsub(/\s*\/\s*/, "/")          # normalize " / " to "/"
      .gsub(/\s*-\s*/, " - ")         # normalize dash spacing
      .gsub(/\s+/, " ")               # collapse whitespace
      .gsub(/[.,!\-]+\z/, "")         # strip trailing punctuation
      .strip
  end

  def self.normalize_company(c)
    return nil if c.blank?
    c.downcase.strip
      .gsub(/,?\s*(inc\.?|llc\.?|corp\.?|ltd\.?|co\.?|company|corporation|incorporated)\s*$/i, "")
      .gsub(/\s+/, " ").strip
  end

  private

  def set_normalized_fields
    self.normalized_title = self.class.normalize_title(title)
    self.normalized_company = self.class.normalize_company(company)
  end
end

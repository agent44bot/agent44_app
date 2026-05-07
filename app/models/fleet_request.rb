class FleetRequest < ApplicationRecord
  belongs_to :user

  STATUSES = %w[pending contacted onboarded declined].freeze
  SERVICES = {
    "smoke"   => "Smoke testing",
    "monitor" => "Calendar / content monitoring",
    "social"  => "AI-enhanced social posts",
    "custom"  => "Custom agent"
  }.freeze

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def services_list
    services.to_s.split(",").map(&:strip).reject(&:empty?)
  end

  def services_labels
    services_list.map { |s| SERVICES[s] || s }
  end
end

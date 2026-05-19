class ImpersonationLog < ApplicationRecord
  belongs_to :actor,  class_name: "User"
  belongs_to :target, class_name: "User"

  EVENTS = %w[start stop].freeze
  validates :event, inclusion: { in: EVENTS }
end

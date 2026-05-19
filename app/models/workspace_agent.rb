class WorkspaceAgent < ApplicationRecord
  KINDS = %w[list social data test].freeze

  belongs_to :workspace

  validates :kind, presence: true, inclusion: { in: KINDS },
            uniqueness: { scope: :workspace_id }
  validates :agent_number, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 999 },
            uniqueness: { scope: :workspace_id }
  validates :display_name, length: { maximum: 40 }, allow_nil: true

  # Title row label: pet name + badge, or just "<Kind> Agent · #207".
  # Caller already renders the bold/dim treatment.
  def display_label
    if display_name.present?
      "#{display_name} · ##{agent_number}"
    else
      "##{agent_number}"
    end
  end
end

class SavedJob < ApplicationRecord
  belongs_to :user
  belongs_to :job

  validates :job_id, uniqueness: { scope: :user_id }

  def applied?
    applied_at.present?
  end

  def toggle_applied!
    update!(applied_at: applied? ? nil : Time.current)
  end
end

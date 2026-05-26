class Credential < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key,  presence: true

  def touch_used!
    update_columns(last_used_at: Time.current)
  end
end

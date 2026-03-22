class JobSource < ApplicationRecord
  belongs_to :job

  validates :source, :url, presence: true
  validates :url, uniqueness: { scope: :source }
  validates :source, uniqueness: { scope: :job_id }
end

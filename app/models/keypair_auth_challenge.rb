class KeypairAuthChallenge < ApplicationRecord
  EXPIRY_DURATION = 5.minutes
  CHALLENGE_BYTES = 32

  validates :challenge, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where(consumed: false).where("expires_at > ?", Time.current) }

  before_validation :generate_challenge, on: :create
  before_validation :set_expiry, on: :create

  def expired?
    expires_at <= Time.current
  end

  def consume!
    update!(consumed: true)
  end

  def valid_for_use?
    !consumed? && !expired?
  end

  private

  def generate_challenge
    self.challenge ||= SecureRandom.hex(CHALLENGE_BYTES)
  end

  def set_expiry
    self.expires_at ||= EXPIRY_DURATION.from_now
  end
end

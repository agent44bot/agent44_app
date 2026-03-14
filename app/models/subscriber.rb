class Subscriber < ApplicationRecord
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end
end

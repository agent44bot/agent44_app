class Session < ApplicationRecord
  belongs_to :user
  belongs_to :impersonated_user, class_name: "User", optional: true

  def effective_user
    impersonated_user || user
  end

  def impersonating?
    impersonated_user_id.present?
  end
end

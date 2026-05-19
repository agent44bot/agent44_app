class Current < ActiveSupport::CurrentAttributes
  attribute :session

  # The user the app is rendering as. When an admin is impersonating, this is
  # the impersonated user. Otherwise it's the session's real user.
  def user
    session&.effective_user
  end

  # The actual signed-in user, ignoring any active impersonation. Use this for
  # admin gates and audit trails so we always know who's really driving.
  def real_user
    session&.user
  end
end

class RefreshXTokensJob < ApplicationJob
  queue_as :default

  REFRESH_LEAD_TIME = 30.minutes

  def perform
    return unless X::Oauth.configured?

    accounts = SocialAccount.for_platform("x").active.where("token_expires_at IS NULL OR token_expires_at <= ?", REFRESH_LEAD_TIME.from_now)
    accounts.find_each { |acct| refresh_one(acct) }
  end

  private

  def refresh_one(acct)
    if acct.refresh_token.blank?
      acct.mark_needs_reauth!
      return
    end

    result = X::Oauth.refresh(refresh_token: acct.refresh_token)
    if result.ok?
      acct.update!(
        access_token:     result.access_token,
        refresh_token:    result.refresh_token.presence || acct.refresh_token,
        token_expires_at: result.expires_in ? Time.current + result.expires_in.to_i.seconds : nil,
        scopes:           result.scope.presence || acct.scopes,
        status:           "active",
        last_synced_at:   Time.current
      )
    elsif result.retryable?
      # Transient X outage / rate limit / network blip: leave the account
      # active so the next scheduled run retries. Marking it needs_reauth here
      # would strand it (this job only refreshes active accounts).
      Rails.logger.warn("X token refresh transient failure for SocialAccount ##{acct.id}: #{result.error} (will retry)")
    else
      Rails.logger.warn("X token refresh failed for SocialAccount ##{acct.id}: #{result.error}")
      acct.mark_needs_reauth!
    end
  end
end

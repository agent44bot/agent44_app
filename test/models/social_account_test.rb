require "test_helper"

class SocialAccountTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email_address: "sa-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "SA Test", owner: @owner)
  end

  test "access_token, refresh_token, token_secret are encrypted at rest" do
    @ws.social_accounts.create!(
      platform: "x", connected_by: @owner, handle: "@enc",
      external_id: SecureRandom.hex(4),
      access_token: "PLAINTEXT-ACCESS",
      refresh_token: "PLAINTEXT-REFRESH",
      token_secret: "PLAINTEXT-SECRET",
      status: "active"
    )
    acct = @ws.social_accounts.first

    raw = SocialAccount.connection.select_one(
      "SELECT access_token, refresh_token, token_secret FROM social_accounts WHERE id = #{acct.id}"
    )

    # Encrypted columns land as JSON envelopes (e.g. {"p":"...","h":{...}})
    %w[access_token refresh_token token_secret].each do |col|
      refute_equal "PLAINTEXT-#{col.upcase.sub('_TOKEN','').sub('_SECRET','')}", raw[col],
        "#{col} should not be stored as plaintext"
      assert_match(/\A\{.*\}\z/, raw[col], "#{col} should be a JSON envelope")
    end

    # Accessors decrypt cleanly
    assert_equal "PLAINTEXT-ACCESS",  acct.access_token
    assert_equal "PLAINTEXT-REFRESH", acct.refresh_token
    assert_equal "PLAINTEXT-SECRET",  acct.token_secret
  end

  test "expired? reflects token_expires_at" do
    acct = @ws.social_accounts.create!(platform: "x", handle: "@e", external_id: "1",
      token_expires_at: 5.minutes.ago, status: "active")
    assert acct.expired?

    acct.update!(token_expires_at: 1.hour.from_now)
    refute acct.expired?
  end

  test "mark_needs_reauth! flips status" do
    acct = @ws.social_accounts.create!(platform: "x", handle: "@e", external_id: "2", status: "active")
    acct.mark_needs_reauth!
    assert_equal "needs_reauth", acct.reload.status
  end
end

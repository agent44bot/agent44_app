require "test_helper"

class WeeklySalesEmailJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    owner = User.create!(email_address: "owner-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @workspace = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = owner }
    snapshot = KitchenSnapshot.create!(taken_on: Date.current)
    snapshot.kitchen_events.create!(
      url: "https://nykitchen.com/e1", name: "Class A", start_at: 3.days.from_now,
      availability: "InStock", price: "100.00", capacity: 10, spots_left: 4
    )
  end

  test "skips sending when no one has opted in" do
    assert_no_emails { WeeklySalesEmailJob.perform_now }
  end

  test "emails the opted-in subscribers" do
    user = User.create!(email_address: "sub-#{SecureRandom.hex(4)}@example.com", role: "user")
    @workspace.agent_for("analyst").update_settings(weekly_email_subscriber_ids: [ user.id ])

    assert_emails 1 do
      WeeklySalesEmailJob.perform_now
    end
    mail = ActionMailer::Base.deliveries.last
    assert_includes mail.to, user.email_address
    assert_match "your team's week", mail.subject
  end

  test "weekly_social summarizes this week's posts + engagement when accounts exist" do
    assert_nil WeeklySalesEmailJob.weekly_social(Date.current - 7), "nil when no connected accounts"

    acct = @workspace.social_accounts.create!(platform: "x", connected_by: @workspace.owner,
      handle: "@nyk", external_id: SecureRandom.hex(4), access_token: "AT", refresh_token: "RT",
      token_expires_at: 2.hours.from_now, status: "active")
    @workspace.workspace_posts.create!(author: @workspace.owner, social_account: acct, platform: "x",
      body: "this week", status: "posted", posted_at: 2.days.ago, remote_id: "1", likes: 5, reposts: 2, replies: 1)
    @workspace.workspace_posts.create!(author: @workspace.owner, social_account: acct, platform: "x",
      body: "too old", status: "posted", posted_at: 20.days.ago, remote_id: "2", likes: 99)

    echo = WeeklySalesEmailJob.weekly_social(Date.current - 7)
    assert_equal 1, echo[:posts]            # only the in-window post
    assert_equal 5, echo[:likes]
    assert_equal({ "x" => 1 }, echo[:by_platform])
  end

  test "skips a subscriber with no email on file" do
    user = User.create!(role: "user", pubkey_hex: SecureRandom.hex(32)) # Nostr user, no email_address
    @workspace.agent_for("analyst").update_settings(weekly_email_subscriber_ids: [ user.id ])
    assert_no_emails { WeeklySalesEmailJob.perform_now }
  end
end

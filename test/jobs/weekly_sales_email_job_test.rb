require "test_helper"

class WeeklySalesEmailJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @owner = User.create!(email_address: "owner-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @workspace = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @owner }
    snapshot = KitchenSnapshot.create!(taken_on: Date.current)
    snapshot.kitchen_events.create!(
      url: "https://nykitchen.com/e1", name: "Class A", start_at: 3.days.from_now,
      availability: "InStock", price: "100.00", capacity: 10, spots_left: 4
    )
  end

  test "build_summary with carson: false produces no headline (no AI call)" do
    snapshot = KitchenSnapshot.latest
    # Stub carson_intro so a regression that calls it despite carson:false is
    # caught even though carson_intro is a no-op in test env.
    called = false
    WeeklySalesEmailJob.define_singleton_method(:carson_intro) { |_| called = true; "INTRO" }
    begin
      summary = WeeklySalesEmailJob.build_summary(snapshot, carson: false)
      assert_nil summary[:headline]
      assert_not called, "carson_intro must not be called when carson: false"
    ensure
      WeeklySalesEmailJob.singleton_class.send(:remove_method, :carson_intro)
    end
  end

  test "skips sending when no workspace member has an email" do
    # Drop the email-bearing owner membership; leave only a Nostr member.
    @workspace.memberships.destroy_all
    nostr = User.create!(role: "user", pubkey_hex: SecureRandom.hex(32))
    @workspace.memberships.create!(user: nostr, role: "viewer")
    assert_no_emails { WeeklySalesEmailJob.perform_now }
  end

  test "emails every workspace member" do
    member = User.create!(email_address: "member-#{SecureRandom.hex(4)}@example.com", role: "user")
    @workspace.memberships.create!(user: member, role: "admin")

    # Owner + member = 2 recipients on one email.
    assert_emails 1 do
      WeeklySalesEmailJob.perform_now
    end
    mail = ActionMailer::Base.deliveries.last
    assert_includes mail.to, @owner.email_address
    assert_includes mail.to, member.email_address
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

  test "skips a member with no email but still emails the rest" do
    nostr = User.create!(role: "user", pubkey_hex: SecureRandom.hex(32)) # no email_address
    @workspace.memberships.create!(user: nostr, role: "viewer")
    assert_emails 1 do # only the email-bearing owner gets it
      WeeklySalesEmailJob.perform_now
    end
    assert_not_includes ActionMailer::Base.deliveries.last.to, nil
  end
end

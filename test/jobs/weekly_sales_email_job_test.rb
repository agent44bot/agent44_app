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
    # Keep a handle on the real method: remove_method here would DELETE it
    # (define_singleton_method overwrites it on the singleton class), making
    # every later carson: true test in this process fail with NoMethodError
    # depending on seed order.
    original = WeeklySalesEmailJob.method(:carson_intro)
    WeeklySalesEmailJob.define_singleton_method(:carson_intro) { |_| called = true; "INTRO" }
    begin
      summary = WeeklySalesEmailJob.build_summary(snapshot, carson: false)
      assert_nil summary[:headline]
      assert_not called, "carson_intro must not be called when carson: false"
    ensure
      WeeklySalesEmailJob.define_singleton_method(:carson_intro, original)
    end
  end

  test "booked_week label and delta period track the send day" do
    snapshot = KitchenSnapshot.latest
    # Monday: headline is the finished last week, delta compares the week before.
    travel_to Time.zone.parse("2026-06-08 10:00") do
      bw = WeeklySalesEmailJob.build_summary(snapshot, carson: false)[:booked_week]
      assert_match "last week", bw[:label]
      assert_equal "vs prior week", bw[:compare_label]
    end
    # Friday: headline is this week so far, delta compares last week.
    travel_to Time.zone.parse("2026-06-12 10:00") do
      bw = WeeklySalesEmailJob.build_summary(snapshot, carson: false)[:booked_week]
      assert_match "this week", bw[:label]
      assert_equal "vs last week", bw[:compare_label]
    end
  end

  test "a changelog entry with a link renders a button in the report (html + text)" do
    summary = WeeklySalesEmailJob.build_summary(KitchenSnapshot.latest, carson: false)
    summary[:changelog] = [ { date: Date.current, note: "Shiny new thing",
                              link: "/nykitchen/analyst", link_label: "Open the Analyst dashboard" } ]
    mail = KitchenMailer.weekly_sales(summary, recipients: [ "x@example.com" ])

    html = mail.html_part.body.to_s
    assert_match "Open the Analyst dashboard", html
    assert_match "https://agent44labs.com/nykitchen/analyst", html
    assert_match "https://agent44labs.com/nykitchen/analyst", mail.text_part.body.to_s
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

  test "perform stamps the last-sent time when an email goes out" do
    assert_nil Setting.time("nyk_weekly_report:last_sent_at")
    WeeklySalesEmailJob.perform_now
    assert_not_nil Setting.time("nyk_weekly_report:last_sent_at"), "should record the send time"
  end

  test "recipient_engagement flags only dashboard visits after the last send" do
    # Owner viewed the dashboard AFTER the send; a second member did not.
    member = User.create!(email_address: "member-#{SecureRandom.hex(4)}@example.com", role: "user")
    @workspace.memberships.create!(user: member, role: "admin")

    Setting.touch_time("nyk_weekly_report:last_sent_at")
    last_sent = Setting.time("nyk_weekly_report:last_sent_at")

    # A pre-send visit must NOT count; a post-send visit must.
    PageView.create!(user_id: @owner.id, path: "/nykitchen/analyst", method: "GET", created_at: last_sent - 1.hour)
    PageView.create!(user_id: @owner.id, path: "/nykitchen/analyst", method: "GET", created_at: last_sent + 5.minutes)

    eng = WeeklySalesEmailJob.recipient_engagement
    owner_row  = eng[:rows].find { |r| r[:user].id == @owner.id }
    member_row = eng[:rows].find { |r| r[:user].id == member.id }

    assert_not_nil owner_row[:viewed_at], "owner visited after the send"
    assert owner_row[:viewed_at] >= last_sent
    assert_nil member_row[:viewed_at], "member never visited"
    # Engaged recipients sort ahead of non-engaged ones.
    assert_equal @owner.id, eng[:rows].first[:user].id
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

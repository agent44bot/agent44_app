require "test_helper"
require "minitest/mock"

# EchoDailyEmailJob mails each member of a listening workspace the conversations
# Echo found since the last send. No network or AI here (SocialListenJob does the
# finding); this only covers who gets mailed, and when nothing is mailed.
class EchoDailyEmailJobTest < ActiveJob::TestCase
  setup do
    Setting.delete_all
    ActionMailer::Base.deliveries.clear
    @rich = User.create!(email_address: "rich-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @lora = User.create!(email_address: "lora-#{SecureRandom.hex(4)}@example.com")
    @ws = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @rich }
    @ws.memberships.destroy_all
    @ws.memberships.create!(user: @rich, role: "owner")
    @lora_membership = @ws.memberships.create!(user: @lora, role: "admin")
    Setting.set("social_listen:slugs", "nykitchen")
  end

  def lead(created_at: Time.current, **attrs)
    @ws.social_leads.create!({
      platform: "x", external_id: SecureRandom.hex(6), author: "flxfoodie",
      text: "any good cooking class in the Finger Lakes?", url: "https://x.com/flxfoodie/status/1",
      posted_at: 1.day.ago, score: 80, reason: "local intent", draft_reply: "Come cook with us!",
      status: "new", created_at: created_at
    }.merge(attrs))
  end

  test "every member is signed up by default and gets their own email" do
    lead

    EchoDailyEmailJob.perform_now

    assert_equal 2, ActionMailer::Base.deliveries.size, "one email per member, not one to-all"
    assert_equal [ @lora.email_address, @rich.email_address ].sort,
                 ActionMailer::Base.deliveries.flat_map(&:to).sort
  end

  test "a member who turned the email off is skipped" do
    lead
    @lora_membership.update!(echo_email_enabled: false)

    EchoDailyEmailJob.perform_now

    assert_equal [ @rich.email_address ], ActionMailer::Base.deliveries.flat_map(&:to)
  end

  test "sends nothing on a day with no new conversations" do
    EchoDailyEmailJob.perform_now

    assert_empty ActionMailer::Base.deliveries
    assert Setting.time("echo_email:last_sent_at:nykitchen"), "a quiet day still stamps the run"
  end

  test "only mails conversations found since the last send" do
    Setting.set("echo_email:last_sent_at:nykitchen", 2.hours.ago.iso8601)
    lead(created_at: 4.hours.ago, text: "already emailed yesterday")
    lead(created_at: 30.minutes.ago, text: "brand new conversation")

    EchoDailyEmailJob.perform_now

    body = ActionMailer::Base.deliveries.first.body.to_s
    assert_match "brand new conversation", body
    assert_no_match(/already emailed yesterday/, body)
  end

  test "skips leads already replied to or dismissed on the Echo page" do
    lead(status: "sent", text: "already replied")
    lead(status: "dismissed", text: "not for us")

    EchoDailyEmailJob.perform_now

    assert_empty ActionMailer::Base.deliveries
  end

  test "the first run only looks back a day, not at the whole backlog" do
    lead(created_at: 5.days.ago, text: "stale backlog lead")
    lead(created_at: 2.hours.ago, text: "todays lead")

    EchoDailyEmailJob.perform_now

    body = ActionMailer::Base.deliveries.first.body.to_s
    assert_match "todays lead", body
    assert_no_match(/stale backlog lead/, body)
  end

  test "extra configured addresses are emailed too, without double-mailing a member" do
    lead
    Setting.set("social_listen:notify_emails", "agency@example.com, #{@rich.email_address}")

    EchoDailyEmailJob.perform_now

    to = ActionMailer::Base.deliveries.flat_map(&:to)
    assert_includes to, "agency@example.com"
    assert_equal 1, to.count(@rich.email_address), "a member on both lists gets one email"
  end

  test "does nothing for a workspace Echo is not listening to" do
    lead
    Setting.set("social_listen:slugs", "")

    EchoDailyEmailJob.perform_now

    assert_empty ActionMailer::Base.deliveries
  end

  test "one failing recipient does not stop the rest, and the run is still stamped" do
    lead
    # Bound up front so the stub can delegate without re-entering itself.
    original = EchoMailer.method(:new_leads)
    EchoMailer.stub :new_leads, ->(**kwargs) {
      raise Net::SMTPFatalError, "550 bad address" if kwargs[:recipient] == @rich.email_address
      original.call(**kwargs)
    } do
      EchoDailyEmailJob.perform_now
    end

    assert_equal [ @lora.email_address ], ActionMailer::Base.deliveries.flat_map(&:to)
    assert Setting.time("echo_email:last_sent_at:nykitchen"), "a failed send must not re-mail everyone tomorrow"
  end
end

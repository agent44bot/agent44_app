require "test_helper"

class FeedbackNudgeJobTest < ActiveJob::TestCase
  setup do
    @admin = User.create!(email_address: "rich-#{SecureRandom.hex(3)}@example.com", role: "admin")
    Setting.set(FeedbackAlerts::ALERT_EMAIL_KEY, @admin.email_address)
    @caitlin = User.create!(email_address: "caitlin-#{SecureRandom.hex(3)}@example.com", display_name: "Caitlin", feedback_access: true)
  end

  def item(user, **attrs)
    Feedback.create!(user: user, message: "Add a row mid-list", skip_notifications: true, **attrs)
  end

  test "pushes for a customer item waiting on Rich for over a day" do
    fb = item(@caitlin, status: "planned", planned_at: 3.days.ago)
    assert_difference -> { Notification.where(source: "feedback").count }, 1 do
      FeedbackNudgeJob.perform_now
    end
    n = Notification.last
    assert_equal "Caitlin's feedback has waited 3 days", n.title
    assert_equal "/admin/feedbacks/#{fb.id}", n.url
    assert_match "Plan ready", n.body
  end

  test "stuck items count, using their last change" do
    fb = item(@caitlin, status: "approved", agent_error: "boom")
    fb.update_column(:updated_at, 2.days.ago)
    assert_difference -> { Notification.count }, 1 do
      FeedbackNudgeJob.perform_now
    end
  end

  test "skips fresh items, admin items, and items not waiting on Rich" do
    item(@caitlin, status: "pr_ready", pr_ready_at: 2.hours.ago)
    item(@admin, status: "planned", planned_at: 3.days.ago)
    item(@caitlin, status: "approved", updated_at: 3.days.ago)
    item(@caitlin, status: "shipped", planned_at: 3.days.ago)
    assert_no_difference -> { Notification.count } do
      FeedbackNudgeJob.perform_now
    end
  end
end

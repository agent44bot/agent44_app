require "test_helper"

class FeedbackSubmittedJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @admin = User.create!(email_address: "rich-#{SecureRandom.hex(3)}@example.com", role: "admin")
    Setting.set(FeedbackAlerts::ALERT_EMAIL_KEY, @admin.email_address)
    @user = User.create!(email_address: "caitlin-#{SecureRandom.hex(3)}@example.com", display_name: "Caitlin", feedback_access: true)
    @fb = Feedback.create!(user: @user, message: "Keep every recipe on one page please")
    @fb.attachments.attach(io: file_fixture("sample_bottle.png").open, filename: "shot.png", content_type: "image/png")
  end

  test "pushes Rich and acknowledges the sender, with no inbox copy" do
    assert_difference -> { Notification.count }, 1 do
      assert_enqueued_emails 1 do
        FeedbackSubmittedJob.perform_now(@fb)
      end
    end
    n = Notification.last
    assert_equal "feedback", n.source
    assert_equal @admin.id, n.user_id
    assert_equal "Feedback from Caitlin", n.title
    assert_equal "/admin/feedbacks/#{@fb.id}", n.url
    assert_match "one page", n.body
  end

  test "the acknowledgement and Live emails go to the sender with no dashes" do
    [ FeedbackMailer.received(@fb), FeedbackMailer.shipped(@fb) ].each do |mail|
      assert_equal [ @user.email_address ], mail.to
      assert_no_match(/[—–]/, mail.html_part.body.to_s + mail.text_part.body.to_s + mail.subject)
    end
  end
end

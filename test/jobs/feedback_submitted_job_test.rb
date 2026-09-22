require "test_helper"

class FeedbackSubmittedJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @admin = User.create!(email_address: "rich-#{SecureRandom.hex(3)}@example.com", role: "admin")
    Setting.set(FeedbackSubmittedJob::ALERT_EMAIL_KEY, @admin.email_address)
    @user = User.create!(email_address: "caitlin-#{SecureRandom.hex(3)}@example.com", display_name: "Caitlin")
    @fb = Feedback.create!(user: @user, message: "Keep every recipe on one page please")
    @fb.attachments.attach(io: file_fixture("sample_bottle.png").open, filename: "shot.png", content_type: "image/png")
  end

  test "pushes Rich, emails a copy to the inbox, and acknowledges the sender" do
    assert_difference -> { Notification.count }, 1 do
      assert_enqueued_emails 2 do
        FeedbackSubmittedJob.perform_now(@fb)
      end
    end
    n = Notification.last
    assert_equal "feedback", n.source
    assert_equal @admin.id, n.user_id
    assert_equal "Feedback from Caitlin", n.title
    assert_match "one page", n.body
  end

  test "the inbox copy carries the files and replies to the sender" do
    mail = FeedbackMailer.copy(@fb, to: FeedbackSubmittedJob::DEFAULT_COPY_EMAIL)
    assert_equal [ "agent44bot@gmail.com" ], mail.to
    assert_equal [ @user.email_address ], mail.reply_to
    assert_equal [ "shot.png" ], mail.attachments.map(&:filename)
    assert_match "Keep every recipe on one page", mail.html_part.body.to_s
  end

  test "the acknowledgement and Live emails go to the sender with no dashes" do
    [ FeedbackMailer.received(@fb), FeedbackMailer.shipped(@fb) ].each do |mail|
      assert_equal [ @user.email_address ], mail.to
      assert_no_match(/[—–]/, mail.html_part.body.to_s + mail.text_part.body.to_s + mail.subject)
    end
  end
end

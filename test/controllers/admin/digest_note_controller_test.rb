require "test_helper"

class Admin::DigestNoteControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "note-admin-#{SecureRandom.hex(4)}@example.com", role: "admin")
  end

  test "non-admins are redirected" do
    sign_in_as User.create!(email_address: "note-user-#{SecureRandom.hex(4)}@example.com")
    get admin_digest_note_path
    assert_response :redirect
    assert_nil Setting.get(KitchenDigestEmailJob::NOTE_HEADING_KEY)
  end

  test "admin saves heading, note, and date" do
    sign_in_as @admin
    get admin_digest_note_path
    assert_response :success

    patch admin_digest_note_path, params: { heading: "From Rich", note: "Great class", note_on: "2026-10-10" }
    assert_redirected_to admin_digest_note_path
    assert_equal "From Rich", KitchenDigestEmailJob.note_heading
    assert_equal "Great class", KitchenDigestEmailJob.note_for(Date.new(2026, 10, 10))
  end

  test "blank heading falls back to the default" do
    sign_in_as @admin
    patch admin_digest_note_path, params: { heading: "", note: "Hi", note_on: "2026-10-10" }
    assert_equal KitchenDigestEmailJob::DEFAULT_NOTE_HEADING, KitchenDigestEmailJob.note_heading
  end

  test "clear removes the note" do
    sign_in_as @admin
    Setting.set(KitchenDigestEmailJob::NOTE_KEY, "Hi")
    Setting.set(KitchenDigestEmailJob::NOTE_ON_KEY, "2026-10-10")
    patch admin_digest_note_path, params: { clear: "Clear note" }
    assert_nil KitchenDigestEmailJob.note_for(Date.new(2026, 10, 10))
  end

  test "send_test emails only the signed-in admin" do
    sign_in_as @admin
    KitchenSnapshot.create!(taken_on: Date.today)
    Setting.set(KitchenDigestEmailJob::NOTE_KEY, "Great class")

    assert_emails 1 do
      post admin_digest_note_test_path
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ @admin.email_address ], mail.to
    assert_match "[TEST]", mail.subject
    assert_includes mail.body.encoded, "Great class"
  end
end

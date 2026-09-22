require "test_helper"

class FeedbacksTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @owner = User.create!(email_address: "fb-owner-#{SecureRandom.hex(3)}@example.com")
    @ws = Workspace.create!(name: "Finger Lakes Culinary", slug: "flc#{SecureRandom.hex(2)}", owner: @owner)
    @user = User.create!(email_address: "caitlin-#{SecureRandom.hex(3)}@example.com", display_name: "Caitlin")
    @ws.memberships.create!(user: @user, role: "editor")
    @admin = User.create!(email_address: "rich-#{SecureRandom.hex(3)}@example.com", role: "admin")
  end

  def image = fixture_file_upload("sample_bottle.png", "image/png")

  test "signed-out visitors are sent to sign in" do
    get new_feedback_path
    assert_redirected_to sign_in_path
  end

  test "a non-admin workspace member can open the form, and it remembers the page they came from" do
    sign_in_as @user
    get new_feedback_path(from: "/#{@ws.slug}/packets/90/edit?tab=1")
    assert_response :success
    assert_select "input[type=hidden][name='feedback[page_url]'][value=?]", "/#{@ws.slug}/packets/90/edit?tab=1"
    assert_select "textarea[name='feedback[message]']"
    assert_select "input[type=file][name='feedback[attachments][]'][multiple]"
  end

  test "an outside URL is never kept as the page" do
    sign_in_as @user
    get new_feedback_path(from: "https://evil.example.com/phish")
    assert_select "input[type=hidden][name='feedback[page_url]']:not([value])"
  end

  test "submitting saves the message, files, page and workspace, then fans out" do
    sign_in_as @user
    assert_difference -> { Feedback.count }, 1 do
      assert_enqueued_with(job: FeedbackSubmittedJob) do
        post feedbacks_path, params: { feedback: {
          message: "Please add a gap between ingredient lists.",
          page_url: "/#{@ws.slug}/packets/90/edit",
          attachments: [ image, image ] } }
      end
    end
    assert_redirected_to feedbacks_path
    fb = Feedback.last
    assert_equal @user, fb.user
    assert_equal @ws, fb.workspace, "inferred from the page's first path segment"
    assert_equal "received", fb.status
    assert_equal 2, fb.attachments.size

    follow_redirect!
    assert_match "Please add a gap", response.body
  end

  test "a blank message is refused with the form re-shown" do
    sign_in_as @user
    assert_no_difference -> { Feedback.count } do
      post feedbacks_path, params: { feedback: { message: " " } }
    end
    assert_response :unprocessable_entity
  end

  test "a file type we don't take is refused" do
    sign_in_as @user
    exe = Rack::Test::UploadedFile.new(StringIO.new("MZ"), "application/x-msdownload", original_filename: "tool.exe")
    assert_no_difference -> { Feedback.count } do
      post feedbacks_path, params: { feedback: { message: "see file", attachments: [ exe ] } }
    end
    assert_response :unprocessable_entity
    assert_match "tool.exe", response.body
  end

  test "each user sees only their own feedback" do
    other = User.create!(email_address: "other-#{SecureRandom.hex(3)}@example.com")
    Feedback.create!(user: other, message: "Someone else's note")
    Feedback.create!(user: @user, message: "My own note")
    sign_in_as @user
    get feedbacks_path
    assert_match "My own note", response.body
    assert_no_match(/Someone else's note/, response.body)
  end

  test "the nav shows the Feedback button to signed-in users" do
    sign_in_as @user
    get feedbacks_path
    assert_select "a[href^='/feedback/new']"
  end

  # ---- admin inbox ----

  test "non-admins can't open the admin inbox" do
    sign_in_as @user
    get admin_feedbacks_path
    assert_redirected_to "/workspaces"
  end

  test "Mark Live by hand emails the sender once, with the note" do
    fb = Feedback.create!(user: @user, message: "Drop the Double label")
    sign_in_as @admin
    get admin_feedbacks_path
    assert_response :success
    assert_match "Drop the Double label", response.body

    assert_enqueued_emails 1 do
      post ship_admin_feedback_path(fb), params: { note: "Gone from every packet." }
    end
    assert_redirected_to admin_feedback_path(fb)
    fb.reload
    assert fb.shipped?
    assert_equal "Gone from every packet.", fb.reply
    assert fb.shipped_at

    assert_no_enqueued_emails do
      post ship_admin_feedback_path(fb), params: { note: "" }
    end
    assert_equal "Gone from every packet.", fb.reload.reply, "a blank note keeps the old one"
  end

  test "deleting the user deletes their feedback (Apple delete-account)" do
    Feedback.create!(user: @user, message: "x")
    assert_difference -> { Feedback.count }, -1 do
      @user.destroy!
    end
  end
end

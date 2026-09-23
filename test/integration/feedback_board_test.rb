require "test_helper"

# The feedback board (Rich, 2026-09-22): Pre-dev, Dev, Post-dev, Review PR,
# Deploy and Done, with add, edit, delete and manual moves, all in the app.
class FeedbackBoardTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = User.create!(email_address: "rich-#{SecureRandom.hex(3)}@example.com", role: "admin")
    Setting.set(FeedbackAlerts::ALERT_EMAIL_KEY, @admin.email_address)
    @user = User.create!(email_address: "caitlin-#{SecureRandom.hex(3)}@example.com", display_name: "Caitlin", feedback_access: true)
    sign_in_as @admin
  end

  def item(status, **attrs) = Feedback.create!(user: @user, message: "#{status} item", status: status, **attrs)

  test "each status lands in its column" do
    {
      "received" => "pre_dev", "planned" => "pre_dev", "needs_info" => "pre_dev",
      "changes_requested" => "dev", "pr_ready" => "review_pr",
      "merge_requested" => "deploy", "shipped" => "done", "closed" => "done"
    }.each { |status, stage| assert_equal stage, item(status).stage, status }
    assert_equal "dev", item("approved").stage
    post_dev = item("approved", pr_url: "https://github.com/a/b/pull/1")
    assert_equal "post_dev", post_dev.stage, "a PR still going green"
    assert_equal "Checks running", post_dev.status_label
  end

  test "the board shows every column, with cards where they belong" do
    item("planned")
    item("pr_ready", pr_number: 9, pr_url: "https://github.com/a/b/pull/9", pr_head_sha: "a" * 40, pr_checks: "green")
    item("shipped")
    get admin_feedbacks_path
    assert_response :success
    Feedback::STAGES.each_key { |stage| assert_select "section#stage-#{stage}" }
    assert_select "section#stage-pre_dev", text: /planned item/
    assert_select "section#stage-review_pr", text: /PR #9/
    assert_select "section#stage-done", text: /shipped item/
    assert_match "2 items waiting on you", response.body
  end

  test "+ New item goes into Pre-dev with no push or email to Rich himself" do
    Notification.delete_all
    assert_no_enqueued_jobs(only: FeedbackSubmittedJob) do
      post admin_feedbacks_path, params: { feedback: { message: "Add a dark mode toggle" } }
    end
    fb = Feedback.last
    assert_redirected_to admin_feedback_path(fb)
    assert_equal @admin, fb.user
    assert_equal "pre_dev", fb.stage
    assert_equal 0, Notification.count
  end

  test "an item from the Feedback button still pushes and emails" do
    assert_enqueued_with(job: FeedbackSubmittedJob) { item("received") }
  end

  test "edit the message" do
    fb = item("received")
    patch admin_feedback_path(fb), params: { feedback: { message: "Clearer wording" } }
    assert_equal "Clearer wording", fb.reload.message
  end

  test "delete removes the item" do
    fb = item("received")
    assert_difference -> { Feedback.count }, -1 do
      delete admin_feedback_path(fb)
    end
    assert_redirected_to admin_feedbacks_path
  end

  test "send back to Pre-dev re-plans; reopen brings back a Done item" do
    fb = item("planned", plan: "old plan")
    post reset_admin_feedback_path(fb)
    fb.reload
    assert_equal "received", fb.status
    assert_nil fb.plan

    done = item("closed", closed_at: Time.current)
    post reset_admin_feedback_path(done)
    assert_equal "pre_dev", done.reload.stage
  end

  test "items in Dev through Deploy can't be deleted" do
    %w[approved pr_ready merge_requested].each do |st|
      fb = item(st, pr_url: "https://github.com/a/b/pull/1")
      assert_no_difference -> { Feedback.count }, st do
        delete admin_feedback_path(fb)
      end
    end
  end

  test "sending a PR'd item back to Pre-dev forgets the PR, so a re-approve starts in Dev" do
    fb = item("pr_ready", pr_number: 7, pr_url: "https://github.com/a/b/pull/7", pr_head_sha: "a" * 40,
              pr_checks: "green", ship_note: "old note")
    post reset_admin_feedback_path(fb)
    follow_redirect!
    assert_match "Close PR #7 on GitHub", response.body
    fb.reload
    assert_nil fb.pr_url
    assert_nil fb.pr_head_sha
    assert_nil fb.ship_note
    fb.update!(status: "approved")
    assert_equal "dev", fb.stage
  end

  test "a merge in flight can't be sent back" do
    fb = item("merge_requested", merge_requested_sha: "a" * 40)
    post reset_admin_feedback_path(fb)
    assert_equal "merge_requested", fb.reload.status
  end

  test "the board and CRUD are admin-only" do
    sign_in_as @user
    get admin_feedbacks_path
    assert_redirected_to "/workspaces"
    post admin_feedbacks_path, params: { feedback: { message: "x" } }
    assert_redirected_to "/workspaces"
  end
end

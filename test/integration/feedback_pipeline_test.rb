require "test_helper"

# Phase 2 of the feedback pipeline (docs/feedback_pipeline.md): the Mac mini
# plans and builds through the token API, Rich approves (1) and merges (2) in
# the admin UI, the sender answers questions on their feedback page.
class FeedbackPipelineTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @token = "test-token-#{SecureRandom.hex(8)}"
    ENV["API_TOKEN"] = @token
    @api = { "Authorization" => "Bearer #{@token}" }
    @admin = User.create!(email_address: "rich-#{SecureRandom.hex(3)}@example.com", role: "admin")
    Setting.set(FeedbackAlerts::ALERT_EMAIL_KEY, @admin.email_address)
    @user = User.create!(email_address: "caitlin-#{SecureRandom.hex(3)}@example.com", display_name: "Caitlin", feedback_access: true)
    @fb = Feedback.create!(user: @user, message: "Please remove the QR code from the hero")
    @fb.attachments.attach(io: file_fixture("sample_bottle.png").open, filename: "shot.png", content_type: "image/png")
    Notification.delete_all
  end

  teardown { ENV.delete("API_TOKEN") }

  def api(verb, path, params = {})
    send(verb, path, params: params, headers: @api)
    response.parsed_body
  end

  def pushes = Notification.where(source: "feedback").order(:id).pluck(:title)

  test "the API needs the token" do
    get "/api/v1/feedbacks/queue"
    assert_response :unauthorized
  end

  test "the whole loop: plan, Work on it, PR, Merge it, shipped" do
    # The mini sees a new item that needs a plan, with its attachment.
    q = api(:get, "/api/v1/feedbacks/queue")
    item = q["feedbacks"].find { |f| f["id"] == @fb.id }
    assert_equal "plan", item["step"]
    assert_equal "shot.png", item["attachments"].first["filename"]
    assert_match %r{/rails/active_storage/}, item["attachments"].first["url"]

    api(:post, "/api/v1/feedbacks/#{@fb.id}/claim")
    assert_response :success
    refute api(:get, "/api/v1/feedbacks/queue")["feedbacks"].any? { |f| f["id"] == @fb.id }, "a claimed item is not handed out twice"
    api(:post, "/api/v1/feedbacks/#{@fb.id}/claim")
    assert_response :conflict

    api(:post, "/api/v1/feedbacks/#{@fb.id}/plan", plan: "Remove the phone-only QR under the hero; keep the desktop one.")
    assert_response :success
    assert_equal "planned", @fb.reload.status
    assert_equal [ "Plan ready: Please remove the QR code from the hero" ], pushes

    # The push lands on the item page, which shows the plan and gate (1).
    sign_in_as @admin
    get admin_feedback_path(@fb)
    assert_response :success
    assert_match "Remove the phone-only QR", response.body
    assert_select "form[action='#{approve_admin_feedback_path(@fb)}']"

    post approve_admin_feedback_path(@fb)
    assert_equal "approved", @fb.reload.status

    # The mini builds. Pending checks keep it building, green makes it ready.
    assert_equal "build", api(:get, "/api/v1/feedbacks/queue")["feedbacks"].find { |f| f["id"] == @fb.id }["step"]
    api(:post, "/api/v1/feedbacks/#{@fb.id}/claim")
    pr = { number: 531, url: "https://github.com/agent44bot/agent44_app/pull/531", head_sha: "a" * 40,
           summary: "Removes the QR block.", ship_note: "The QR is gone from the home page." }
    api(:post, "/api/v1/feedbacks/#{@fb.id}/pr", pr.merge(checks: "pending"))
    assert_equal "approved", @fb.reload.status
    api(:post, "/api/v1/feedbacks/#{@fb.id}/pr", pr.merge(checks: "green"))
    assert_equal "pr_ready", @fb.reload.status
    assert_equal "Ready to merge: Please remove the QR code from the hero", pushes.last

    # Gate (2): the item page links the PR and carries the head SHA.
    get admin_feedback_path(@fb)
    assert_select "a[href='#{pr[:url]}']"
    assert_select "input[name=sha][value=?]", "a" * 40
    post merge_admin_feedback_path(@fb), params: { sha: "a" * 40, note: "The QR is gone. Thanks!" }
    @fb.reload
    assert_equal "merge_requested", @fb.status
    assert_equal "The QR is gone. Thanks!", @fb.ship_note, "Rich's edit to the agent's note wins"

    # The mini merges, verifies the deploy, reports the SHA: sender emailed.
    assert_equal "merge", api(:get, "/api/v1/feedbacks/queue")["feedbacks"].find { |f| f["id"] == @fb.id }["step"]
    assert_enqueued_emails 1 do
      api(:post, "/api/v1/feedbacks/#{@fb.id}/shipped", sha: "a" * 40)
    end
    @fb.reload
    assert @fb.shipped?
    assert_equal "The QR is gone. Thanks!", @fb.reply
    assert_equal "Live: Please remove the QR code from the hero", pushes.last
    refute api(:get, "/api/v1/feedbacks/queue")["feedbacks"].any? { |f| f["id"] == @fb.id }
  end

  test "Merge it refuses a SHA that isn't the PR's latest head, or red checks" do
    @fb.update!(status: "pr_ready", pr_number: 1, pr_url: "https://github.com/x/y/pull/1", pr_head_sha: "b" * 40, pr_checks: "green")
    sign_in_as @admin
    post merge_admin_feedback_path(@fb), params: { sha: "c" * 40 }
    assert_equal "pr_ready", @fb.reload.status
    follow_redirect!
    assert_match "changed since you opened it", response.body

    @fb.update!(pr_checks: "red")
    post merge_admin_feedback_path(@fb), params: { sha: "b" * 40 }
    assert_equal "pr_ready", @fb.reload.status
  end

  test "the mini can't report a different SHA as shipped" do
    @fb.update!(status: "merge_requested", merge_requested_sha: "d" * 40)
    api(:post, "/api/v1/feedbacks/#{@fb.id}/shipped", sha: "e" * 40)
    assert_response :conflict
    assert_equal "merge_requested", @fb.reload.status
  end

  test "the API can't approve or merge: those gates are Rich's" do
    api(:post, "/api/v1/feedbacks/#{@fb.id}/plan", plan: "x")
    assert_raises(ActionController::RoutingError, ActionController::UrlGenerationError) do
      Rails.application.routes.recognize_path("/api/v1/feedbacks/#{@fb.id}/approve", method: :post)
    end
    api(:post, "/api/v1/feedbacks/#{@fb.id}/pr", number: 1, url: "u", head_sha: "f" * 40, checks: "green")
    assert_response :conflict, "a PR can't be reported before Rich approves the plan"
  end

  test "Ask them: the sender answers on their page and it goes back to the agent" do
    api(:post, "/api/v1/feedbacks/#{@fb.id}/plan", plan: "Unclear which QR.", question: "Which QR, the phone one or the desktop one?")
    sign_in_as @admin
    get admin_feedback_path(@fb)
    assert_match "Which QR, the phone one or the desktop one?", response.body, "the agent's question is pre-filled"

    assert_enqueued_emails 1 do
      post ask_admin_feedback_path(@fb), params: { question: "Which QR, the phone one or the desktop one?" }
    end
    assert_equal "needs_info", @fb.reload.status

    sign_in_as @user
    get feedbacks_path
    assert_match "Question for you", response.body
    assert_match "Which QR", response.body
    post answer_feedback_path(@fb), params: { answer: "The phone one at the bottom." }
    @fb.reload
    assert_equal "received", @fb.status
    assert_nil @fb.plan, "the old plan is dropped so the agent re-plans"
    assert_equal "Answer from Caitlin", pushes.last
    assert_equal "plan", @fb.agent_step
    assert_equal %w[draft_question question answer], @fb.thread.map { |t| t["kind"] }
  end

  test "a sender can't answer someone else's feedback" do
    other = User.create!(email_address: "o-#{SecureRandom.hex(3)}@example.com", feedback_access: true)
    @fb.update!(status: "needs_info")
    sign_in_as other
    post answer_feedback_path(@fb), params: { answer: "hi" }
    assert_response :not_found
  end

  test "an error marks it stuck, pushes, drops it from the queue; Retry brings it back" do
    api(:post, "/api/v1/feedbacks/#{@fb.id}/error", message: "claude -p exited 1")
    assert @fb.reload.stuck?
    assert_equal "Stuck: Please remove the QR code from the hero", pushes.last
    refute api(:get, "/api/v1/feedbacks/queue")["feedbacks"].any? { |f| f["id"] == @fb.id }

    sign_in_as @admin
    post retry_admin_feedback_path(@fb)
    refute @fb.reload.stuck?
    assert api(:get, "/api/v1/feedbacks/queue")["feedbacks"].any? { |f| f["id"] == @fb.id }
  end

  test "only a GitHub pull request link is accepted as the PR" do
    @fb.update!(status: "approved")
    api(:post, "/api/v1/feedbacks/#{@fb.id}/pr", number: 1, url: "javascript:alert(1)", head_sha: "a" * 40, checks: "green")
    assert_response :conflict
    assert_equal "approved", @fb.reload.status
    assert_nil @fb.pr_url
  end

  test "a stale claim is handed out again" do
    @fb.update!(agent_claimed_at: 2.hours.ago)
    assert Feedback.agent_queue.include?(@fb)
  end

  test "Request changes sends a green PR back to the agent with the note" do
    @fb.update!(status: "pr_ready", pr_number: 1, pr_url: "https://github.com/x/y/pull/1", pr_head_sha: "b" * 40, pr_checks: "green")
    sign_in_as @admin
    post request_changes_admin_feedback_path(@fb), params: { note: "Keep the desktop QR." }
    @fb.reload
    assert_equal "changes_requested", @fb.status
    assert_equal "build", @fb.agent_step
    assert_equal "Keep the desktop QR.", @fb.thread.last["body"]
  end

  test "the sender never sees the internal steps" do
    @fb.update!(status: "pr_ready")
    sign_in_as @user
    get feedbacks_path
    assert_match "In progress", response.body
    assert_no_match(/Ready to merge/, response.body)
  end
end

require "test_helper"

class PublishDueDraftsJobTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email_address: "pddj-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "Job WS", owner: @owner)
    @ws.social_accounts.create!(
      platform: "x", connected_by: @owner, handle: "@a44",
      external_id: SecureRandom.hex(4), access_token: "AT", refresh_token: "RT",
      token_expires_at: 2.hours.from_now, status: "active"
    )
  end

  teardown { X::UserClient.http_stub = nil }

  test "publishes drafts whose scheduled_for has passed and skips future ones" do
    due = @ws.workspace_drafts.create!(author: @owner, body: "due", target_platforms: %w[x])
    due.update_columns(status: "scheduled", scheduled_for: 30.seconds.ago)
    future = @ws.workspace_drafts.create!(author: @owner, body: "future", target_platforms: %w[x],
                                          status: "scheduled", scheduled_for: 1.hour.from_now)

    X::UserClient.http_stub = ->(*) { { status: "201", body: { "data" => { "id" => "JOB-1" } } } }

    PublishDueDraftsJob.new.perform

    assert_equal "published",  due.reload.status
    assert_equal "scheduled",  future.reload.status
    assert_equal 1, WorkspacePost.where(remote_id: "JOB-1").count
  end

  test "an exception in one draft doesn't stop the job for others" do
    bad = @ws.workspace_drafts.create!(author: @owner, body: "bad", target_platforms: %w[x])
    bad.update_columns(status: "scheduled", scheduled_for: 1.minute.ago)
    good = @ws.workspace_drafts.create!(author: @owner, body: "good", target_platforms: %w[x])
    good.update_columns(status: "scheduled", scheduled_for: 1.minute.ago)

    call_count = 0
    X::UserClient.http_stub = ->(*) {
      call_count += 1
      raise "boom" if call_count == 1
      { status: "201", body: { "data" => { "id" => "GOOD" } } }
    }

    PublishDueDraftsJob.new.perform

    # First draft errored — Publisher#call would have raised, job rescues per-draft.
    # Per-draft rescue marks it failed.
    assert_equal "failed",    bad.reload.status
    assert_equal "published", good.reload.status
  end
end

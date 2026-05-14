require "test_helper"

class WorkspaceDraftTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email_address: "wd-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "Drafts WS", owner: @owner)
  end

  test "target_platforms round-trip via JSON serialization" do
    d = @ws.workspace_drafts.create!(author: @owner, body: "hi", target_platforms: %w[x bluesky])
    assert_equal %w[x bluesky], d.reload.target_platforms
  end

  test "rejects empty platform list" do
    d = @ws.workspace_drafts.build(author: @owner, body: "hi", target_platforms: [])
    refute d.valid?
    assert_includes d.errors[:target_platforms].join, "at least one"
  end

  test "rejects unknown platform" do
    d = @ws.workspace_drafts.build(author: @owner, body: "hi", target_platforms: %w[x faceparty])
    refute d.valid?
    assert_includes d.errors[:target_platforms].join, "faceparty"
  end

  test "scheduled requires future scheduled_for" do
    d = @ws.workspace_drafts.build(author: @owner, body: "hi", target_platforms: %w[x],
                                   status: "scheduled", scheduled_for: 1.hour.ago)
    refute d.valid?
    assert_includes d.errors[:scheduled_for].join, "future"
  end

  test "due_now returns scheduled rows past their fire time" do
    past = @ws.workspace_drafts.create!(author: @owner, body: "past", target_platforms: %w[x], status: "draft")
    past.update_columns(status: "scheduled", scheduled_for: 1.minute.ago)
    @ws.workspace_drafts.create!(author: @owner, body: "future", target_platforms: %w[x],
                                 status: "scheduled", scheduled_for: 1.hour.from_now)
    assert_includes WorkspaceDraft.due_now.pluck(:id), past.id
    refute WorkspaceDraft.due_now.where("scheduled_for > ?", Time.current).exists?
  end
end

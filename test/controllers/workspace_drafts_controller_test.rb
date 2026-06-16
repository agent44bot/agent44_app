require "test_helper"

class WorkspaceDraftsControllerTest < ActionDispatch::IntegrationTest
  setup do
    owner   = User.create!(email_address: "wd-o-#{SecureRandom.hex(4)}@example.com", role: "user")
    @ws     = Workspace.create!(name: "NYK", owner: owner, slug: "nykitchen")
    @writer = User.create!(email_address: "wd-w-#{SecureRandom.hex(4)}@example.com", role: "user")
    @ws.memberships.create!(user: @writer, role: "editor")
    @draft  = @ws.workspace_drafts.create!(author: @writer, body: "hello", target_platforms: %w[x], status: "draft")
    sign_in_as(@writer)
  end

  test "Back button returns to Sam's list when arrived via return_to" do
    get edit_workspace_draft_path(workspace_slug: @ws.slug, id: @draft.id, return_to: "/nykitchen/list")
    assert_response :success
    assert_select "a[href=?]", "/nykitchen/list", text: /Back to Sam's list/
  end

  test "Back button defaults to the workspace social page without return_to" do
    get edit_workspace_draft_path(workspace_slug: @ws.slug, id: @draft.id)
    assert_response :success
    assert_select "a[href=?]", social_workspace_path(@ws.slug), text: /Back to workspace/
  end

  test "an off-site return_to is ignored (no open redirect)" do
    get edit_workspace_draft_path(workspace_slug: @ws.slug, id: @draft.id, return_to: "//evil.com")
    assert_response :success
    assert_select "a[href=?]", "//evil.com", count: 0
    assert_select "a[href=?]", social_workspace_path(@ws.slug), text: /Back to workspace/
  end
end

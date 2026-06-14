require "test_helper"

# Deleting a workspace is owner-only. A workspace admin (e.g. a customer
# contact like Lora) can manage the team and content but must NOT be able to
# delete the workspace.
class WorkspaceDeletePermissionTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "del-o-#{SecureRandom.hex(4)}@example.com")
    @admin = User.create!(email_address: "del-a-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "Delete WS", owner: @owner)
    @ws.memberships.create!(user: @admin, role: "admin")
  end

  test "owner can delete the workspace" do
    sign_in_as(@owner)
    assert_difference -> { Workspace.count }, -1 do
      delete workspace_path(@ws.slug)
    end
    assert_redirected_to workspaces_path
  end

  test "an admin cannot delete the workspace" do
    sign_in_as(@admin)
    assert_no_difference -> { Workspace.count } do
      delete workspace_path(@ws.slug)
    end
    assert_redirected_to workspace_path(@ws.slug)
    assert_match(/Only the workspace owner/, flash[:alert])
  end

  test "the Danger zone is hidden from a non-owner admin on the overview" do
    sign_in_as(@admin)
    get workspace_path(@ws.slug)
    assert_response :success
    assert_select "h2", text: /Danger zone/, count: 0
    # but the admin still sees team management
    assert_select "h2", text: /Invite a teammate/
  end

  test "the owner sees the Danger zone" do
    sign_in_as(@owner)
    get workspace_path(@ws.slug)
    assert_select "h2", text: /Danger zone/
  end
end

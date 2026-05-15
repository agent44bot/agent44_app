require "test_helper"

# Verifies the dogfood-phase gate: only site admins can touch Fleet
# Social. Members, reviewers, kitchen_customers all bounce to root with
# the private-beta alert. When we open Fleet Social to broader roles,
# update FleetSocialAccess#require_fleet_social_access and these tests.
class FleetSocialAccessTest < ActionDispatch::IntegrationTest
  setup do
    @admin   = User.create!(email_address: "fsa-a-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @member  = User.create!(email_address: "fsa-m-#{SecureRandom.hex(4)}@example.com", role: "member")
    @ws      = Workspace.create!(name: "Gated WS", owner: @admin)
  end

  test "admin can reach the workspaces index" do
    sign_in_as(@admin)
    get workspaces_path
    assert_response :success
  end

  test "member is redirected to root with the private-beta alert" do
    sign_in_as(@member)
    get workspaces_path
    assert_redirected_to root_path
    assert_match /private beta/i, flash[:alert]
  end

  test "member cannot create a workspace" do
    sign_in_as(@member)
    assert_no_difference -> { Workspace.count } do
      post workspaces_path, params: { workspace: { name: "X", timezone: "UTC" } }
    end
    assert_redirected_to root_path
  end

  test "member cannot view a workspace they're an actual member of" do
    @ws.memberships.create!(user: @member, role: "editor")
    sign_in_as(@member)
    get workspace_path(@ws.slug)
    assert_redirected_to root_path
  end

  test "member cannot post via the composer" do
    @ws.memberships.create!(user: @member, role: "editor")
    sign_in_as(@member)
    assert_no_difference -> { WorkspacePost.count } do
      post workspace_posts_path(workspace_slug: @ws.slug), params: { body: "x", target_platforms: ["x"] }
    end
    assert_redirected_to root_path
  end

  test "member cannot save a draft" do
    @ws.memberships.create!(user: @member, role: "editor")
    sign_in_as(@member)
    assert_no_difference -> { WorkspaceDraft.count } do
      post workspace_drafts_path(workspace_slug: @ws.slug),
           params: { body: "x", target_platforms: ["x"], commit: "save" }
    end
    assert_redirected_to root_path
  end

  test "member cannot trigger any OAuth connect flow" do
    @ws.memberships.create!(user: @member, role: "admin")
    sign_in_as(@member)

    [
      workspace_oauth_x_connect_path(workspace_slug: @ws.slug),
      workspace_oauth_threads_connect_path(workspace_slug: @ws.slug),
      workspace_oauth_facebook_connect_path(workspace_slug: @ws.slug)
    ].each do |path|
      post path
      assert_redirected_to root_path, "expected #{path} to redirect non-admin"
    end
  end

  test "member can't see Workspaces in the mobile nav" do
    sign_in_as(@member)
    get root_path
    refute_match /workspaces.*Workspaces/m, response.body, "non-admins should not see the Workspaces link"
  end
end

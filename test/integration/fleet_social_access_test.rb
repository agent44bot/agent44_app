require "test_helper"

# Verifies the Fleet Social entry gate:
#   - Site admins always pass.
#   - Any user with at least one workspace_membership passes.
#   - Everyone else bounces to root with a "by invitation" alert.
#
# Per-workspace authorization (require_member / require_admin / require_writer)
# still gates each workspace's actions independently — this test only covers
# the outer gate.
class FleetSocialAccessTest < ActionDispatch::IntegrationTest
  setup do
    @admin     = User.create!(email_address: "fsa-a-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @outsider  = User.create!(email_address: "fsa-o-#{SecureRandom.hex(4)}@example.com", role: "member")
    @insider   = User.create!(email_address: "fsa-i-#{SecureRandom.hex(4)}@example.com", role: "member")
    @kitchen   = User.create!(email_address: "fsa-k-#{SecureRandom.hex(4)}@example.com", role: "kitchen_customer")
    @ws        = Workspace.create!(name: "Gated WS", owner: @admin)
    @ws.memberships.create!(user: @insider, role: "editor")
    @ws.memberships.create!(user: @kitchen, role: "editor")
  end

  test "admin can reach workspaces index" do
    sign_in_as(@admin)
    get workspaces_path
    assert_response :success
  end

  test "workspace member can reach workspaces index" do
    sign_in_as(@insider)
    get workspaces_path
    assert_response :success
  end

  test "kitchen_customer who's a workspace member can reach the workspace surface" do
    sign_in_as(@kitchen)
    get workspace_path(@ws.slug)
    assert_response :success
  end

  test "user with no workspace memberships is bounced with by-invitation alert" do
    sign_in_as(@outsider)
    get workspaces_path
    assert_redirected_to root_path
    assert_match /by invitation/i, flash[:alert]
  end

  test "member who's part of a workspace cannot create new workspaces (site-admin gate)" do
    sign_in_as(@insider)
    assert_no_difference -> { Workspace.count } do
      post workspaces_path, params: { workspace: { name: "Mine", timezone: "UTC" } }
    end
    assert_redirected_to workspaces_path
    assert_match /site admins/i, flash[:alert]
  end

  test "non-member can't create a workspace either" do
    sign_in_as(@outsider)
    assert_no_difference -> { Workspace.count } do
      post workspaces_path, params: { workspace: { name: "Mine", timezone: "UTC" } }
    end
    # Outsider bounces at the outer FleetSocialAccess gate before hitting
    # the site-admin check, so they redirect to root not /workspaces.
    assert_redirected_to root_path
  end

  test "writer member can post via the composer" do
    @ws.social_accounts.create!(platform: "x", connected_by: @admin, handle: "@a", external_id: "1",
      access_token: "AT", refresh_token: "RT", token_expires_at: 2.hours.from_now, status: "active")

    sign_in_as(@insider)
    # Stub the X HTTP client so we don't hit the real API
    X::UserClient.http_stub = ->(*) { { status: "201", body: { "data" => { "id" => "TID" } } } }
    assert_difference -> { WorkspacePost.count }, 1 do
      post workspace_posts_path(workspace_slug: @ws.slug), params: { body: "x", target_platforms: ["x"] }
    end
  ensure
    X::UserClient.http_stub = nil
  end

  test "non-member can't even view a workspace they're not in" do
    other = Workspace.create!(name: "Not mine", owner: @admin)
    sign_in_as(@insider)
    get workspace_path(other.slug)
    # Outer gate passes (they're a member of @ws), then require_member on
    # this OTHER workspace fails and bounces to /workspaces with the
    # "not a member of that workspace" alert.
    assert_redirected_to workspaces_path
    assert_match /not a member/i, flash[:alert]
  end

  test "invitation accept flow works for users with no memberships yet" do
    invitee = User.create!(email_address: "fsa-inv-#{SecureRandom.hex(4)}@example.com", role: "member")
    inv = @ws.invitations.create!(invited_by: @admin, email: invitee.email_address, role: "editor")

    sign_in_as(invitee)
    get workspace_invitation_view_path(token: inv.token)
    assert_response :success, "invitation view must be reachable even for non-members"

    post workspace_invitation_accept_path(token: inv.token)
    assert_redirected_to workspace_path(@ws.slug)
    assert @ws.member?(invitee), "invitee should be a member after accept"
  end

  test "Workspaces nav link surfaces for kitchen_customer once they're a member" do
    sign_in_as(@kitchen)
    get nykitchen_path
    assert_response :success
    assert_match /Workspaces/, response.body, "expected the Workspaces nav link for a kitchen_customer who is a workspace member"
  end
end

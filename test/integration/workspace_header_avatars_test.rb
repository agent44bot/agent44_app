require "test_helper"

# The member-avatar stack on a workspace page shows the customer's team, not the
# workspace owner (the Agent44 Labs side). The owner still appears in the team
# management list, just not in the overlapping avatar stack.
class WorkspaceHeaderAvatarsTest < ActionDispatch::IntegrationTest
  test "the avatar stack excludes the owner and shows other members" do
    owner  = User.create!(email_address: "own-#{SecureRandom.hex(4)}@example.com")
    editor = User.create!(email_address: "ed-#{SecureRandom.hex(4)}@example.com")
    ws = Workspace.create!(name: "Team WS", slug: "team-#{SecureRandom.hex(4)}",
                           owner: owner, timezone: "Eastern Time (US & Canada)")
    ws.memberships.create!(user: editor, role: "editor")
    sign_in_as owner

    get workspace_path(ws.slug)
    assert_response :success
    # The overlapping stack container from _member_avatars.
    assert_select "div.-space-x-2" do
      assert_select "[title=?]", owner.display_identifier, count: 0
      assert_select "[title=?]", editor.display_identifier
    end
  end
end

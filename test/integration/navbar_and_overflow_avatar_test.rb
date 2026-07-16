require "test_helper"

class NavbarAndOverflowAvatarTest < ActionDispatch::IntegrationTest
  test "the navbar shows the current user's avatar next to their name" do
    user = User.create!(email_address: "nav-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as user
    get root_path
    assert_response :success
    # The settings link in the nav wraps the avatar (initials span titled with the identifier).
    assert_select "a[href=?] span[title=?]", settings_path, user.display_identifier
  end

  test "the avatar stack renders a hover flyout listing every shown member" do
    owner = User.create!(email_address: "own-#{SecureRandom.hex(4)}@example.com")
    ws = Workspace.create!(name: "Flyout WS", slug: "fly-#{SecureRandom.hex(4)}",
                           owner: owner, timezone: "Eastern Time (US & Canada)")
    editors = 3.times.map do |i|
      u = User.create!(email_address: "ed#{i}-#{SecureRandom.hex(3)}@example.com")
      ws.memberships.create!(user: u, role: "editor")
      u
    end
    sign_in_as owner
    get workspaces_path(force: 1)
    assert_response :success
    # The flyout is in the DOM (shown on hover); it lists each member's identifier.
    editors.each do |u|
      assert_select "p", text: u.display_identifier
    end
  end
end

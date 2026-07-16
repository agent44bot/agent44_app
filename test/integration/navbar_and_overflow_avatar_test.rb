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

  test "the +N overflow chip lists the hidden members in its tooltip" do
    owner = User.create!(email_address: "own-#{SecureRandom.hex(4)}@example.com")
    ws = Workspace.create!(name: "Big WS", slug: "big-#{SecureRandom.hex(4)}",
                           owner: owner, timezone: "Eastern Time (US & Canada)")
    5.times do |i|
      ws.memberships.create!(user: User.create!(email_address: "ed#{i}-#{SecureRandom.hex(3)}@example.com"),
                             role: "editor")
    end
    sign_in_as owner
    get workspaces_path(force: 1)
    assert_response :success
    chip = css_select("span[title]").find { |n| n.text.strip.start_with?("+") }
    assert chip, "expected a +N overflow chip with a tooltip"
    assert_includes chip["title"], "@", "the chip tooltip should list the hidden member email(s)"
  end
end

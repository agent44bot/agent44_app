require "test_helper"

# enforce_workspace_scope sandboxes signed-in non-admins to workspace URLs.
# The marketing home (root) is explicitly allowed so Lora and anyone she invites
# can view it (e.g. to scan the share QR), while other off-limits pages still
# redirect them to /workspaces.
class HomeAccessTest < ActionDispatch::IntegrationTest
  setup do
    @admin     = User.create!(email_address: "home-a-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @non_admin = User.create!(email_address: "home-n-#{SecureRandom.hex(4)}@example.com")
  end

  test "signed-out visitor can see the home page" do
    get "/"
    assert_response :success
  end

  test "non-admin (Lora / invited member) can see the home page" do
    sign_in_as(@non_admin)
    get "/"
    assert_response :success
  end

  test "admin can see the home page" do
    sign_in_as(@admin)
    get "/"
    assert_response :success
  end

  test "hero headline carries the mission line" do
    get "/"
    assert_select "h1", text: /Building agents/
    assert_select "h1 span", text: /for business and everyday life\./
  end

  test "hero headline keeps the first line white" do
    get "/"
    assert_select "h1.text-white"
    assert_select "h1 span.text-purple-400", false
  end

  # Feedback #2 (Rich, 2026-09-22): the phone-only QR pinned under the hero
  # is gone. The only QR left is the desktop one beside the App Store badge.
  test "the page has one QR, the desktop one beside the badge, even for the admin" do
    sign_in_as(@admin)
    get "/"
    assert_select "a[aria-label='Scan or tap to visit agent44labs.ai']", count: 1
    assert_select "section.sm\\:hidden svg", false
    assert_no_match(/qr-code-container/, response.body)
  end

  test "non-admin is still sandboxed off other marketing pages" do
    sign_in_as(@non_admin)
    get "/jobs"
    assert_redirected_to "/workspaces"
  end
end

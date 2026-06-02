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

  test "non-admin is still sandboxed off other marketing pages" do
    sign_in_as(@non_admin)
    get "/jobs"
    assert_redirected_to "/workspaces"
  end
end

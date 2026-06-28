require "test_helper"

# Setting the workspace's website URL (source_url) from workspace Settings.
class WorkspaceSourceUrlTest < ActionDispatch::IntegrationTest
  setup do
    @owner  = User.create!(email_address: "wsu-o-#{SecureRandom.hex(4)}@example.com")
    @editor = User.create!(email_address: "wsu-e-#{SecureRandom.hex(4)}@example.com")
    @ws     = Workspace.create!(name: "URL WS", owner: @owner)
    @ws.memberships.create!(user: @editor, role: "editor")
  end

  test "owner can save a website URL" do
    sign_in_as(@owner)
    assert_changes -> { @ws.reload.source_url }, from: nil, to: "https://gemsofeden.com" do
      patch workspace_path(@ws.slug), params: { workspace: { source_url: "https://gemsofeden.com" } }
    end
    assert_redirected_to workspace_path(@ws.slug)
  end

  test "a blank URL clears it and surrounding whitespace is trimmed" do
    @ws.update_column(:source_url, "https://old.example")
    sign_in_as(@owner)
    patch workspace_path(@ws.slug), params: { workspace: { source_url: "  https://new.example  " } }
    assert_equal "https://new.example", @ws.reload.source_url
    patch workspace_path(@ws.slug), params: { workspace: { source_url: "  " } }
    assert_nil @ws.reload.source_url
  end

  test "a non-http value is rejected with an alert" do
    sign_in_as(@owner)
    patch workspace_path(@ws.slug), params: { workspace: { source_url: "not a url" } }
    assert_nil @ws.reload.source_url
    assert_match(/Update failed/, flash[:alert])
  end

  test "editor (non-admin) cannot change the URL" do
    sign_in_as(@editor)
    patch workspace_path(@ws.slug), params: { workspace: { source_url: "https://x.com" } }
    assert_nil @ws.reload.source_url
    assert_match(/Only workspace admins/, flash[:alert])
  end

  test "the settings panel shows a Website URL field" do
    sign_in_as(@owner)
    get workspace_path(@ws.slug)
    assert_response :success
    assert_select "input[name=?]", "workspace[source_url]"
  end

  test "owner can change the workspace timezone from the settings panel" do
    sign_in_as(@owner)
    patch workspace_path(@ws.slug), params: { workspace: { timezone: "Pacific Time (US & Canada)" } }
    assert_equal "Pacific Time (US & Canada)", @ws.reload.timezone
  end

  test "the settings panel shows a timezone selector" do
    sign_in_as(@owner)
    get workspace_path(@ws.slug)
    assert_select "select[name=?]", "workspace[timezone]"
  end
end

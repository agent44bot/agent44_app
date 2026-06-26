require "test_helper"

# Uploading / removing a profile photo from the Settings page.
class UserAvatarSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "ada-#{SecureRandom.hex(4)}@example.com")
    sign_in_as(@user)
  end

  test "the settings page shows a Profile photo section" do
    get settings_path
    assert_response :success
    assert_match "Profile photo", response.body
  end

  test "uploads a profile photo" do
    patch update_avatar_settings_path,
          params: { avatar: fixture_file_upload("sample_bottle.png", "image/png") }
    assert_redirected_to settings_path
    assert @user.reload.avatar.attached?
  end

  test "removes a profile photo" do
    @user.avatar.attach(io: file_fixture("sample_bottle.png").open, filename: "a.png", content_type: "image/png")
    assert @user.reload.avatar.attached?
    patch update_avatar_settings_path, params: { remove_avatar: "1" }
    assert_redirected_to settings_path
    assert_not @user.reload.avatar.attached?
  end
end

# The Workspaces index header shows real member avatars (initials fallback) plus
# the agent bot, instead of the old stock photos.
class WorkspacesAvatarStackTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "neo-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(@user)
  end

  test "the header shows the current user's avatar and the agent bot" do
    get workspaces_path(force: 1)
    assert_response :success
    assert_select "img[alt=?]", "Agent helper"                  # the bot stays
    assert_select "span[title=?]", @user.display_identifier      # current user's initials chip
  end
end

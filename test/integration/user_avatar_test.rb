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

  test "avatar_display is nil without a photo and resizes once attached" do
    assert_nil @user.avatar_display

    @user.avatar.attach(io: file_fixture("sample_bottle.png").open, filename: "a.png", content_type: "image/png")
    display = @user.reload.avatar_display
    assert_not_nil display
    # Where a variant processor is available it's a 256x256 fill, not the
    # multi-MB original. (Guarded so the test still passes without libvips.)
    if @user.avatar.variable?
      assert_respond_to display, :variation
      assert_equal [ 256, 256 ], display.variation.transformations[:resize_to_fill]
    end
  end

  test "the profile photo form is wired for an instant local preview" do
    get settings_path
    assert_response :success
    assert_select "form[data-controller=?]", "avatar-field"
    assert_select "[data-avatar-field-target=input]"
  end
end

# The Workspaces index header shows real member avatars (initials fallback) plus
# the agent bot, instead of the old stock photos.
class WorkspacesAvatarStackTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "neo-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(@user)
  end

  test "each workspace row shows its member avatars, not a header bot" do
    Workspace.create!(name: "Neo WS", owner: @user)
    get workspaces_path(force: 1)
    assert_response :success
    assert_select "span[title=?]", @user.display_identifier      # member avatar chip on the row
    assert_select "img[alt=?]", "Agent helper", false            # decorative header bot removed
  end
end

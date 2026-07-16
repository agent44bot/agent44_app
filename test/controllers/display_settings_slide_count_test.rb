require "test_helper"

# "Slides to show" is a free-text number field (was a fixed dropdown), so a
# manager can pick any count; the server clamps it to a sane range.
class DisplaySettingsSlideCountTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "disp-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @ws = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @admin }
    sign_in_as(@admin)
  end

  test "a custom slide_count from the number field is saved" do
    patch nyk_display_settings_path, params: { settings: { slide_count: "18" } }
    assert_equal 18, @ws.agent_for("display").setting(:slide_count).to_i
  end

  test "slide_count is clamped to the 1..100 range" do
    patch nyk_display_settings_path, params: { settings: { slide_count: "0" } }
    assert_equal 1, @ws.agent_for("display").setting(:slide_count).to_i

    patch nyk_display_settings_path, params: { settings: { slide_count: "500" } }
    assert_equal 100, @ws.agent_for("display").setting(:slide_count).to_i
  end
end

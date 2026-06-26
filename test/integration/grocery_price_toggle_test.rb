require "test_helper"

# The "Show grocery price estimates" toggle on the NY Kitchen hub. Unlike the
# site-admin billing toggle, this one is a workspace-manager (owner/admin)
# setting so Lora can flip it herself. It defaults OFF: the rough US-average
# grocery estimates stay hidden until real prices are uploaded.
#
# Actors:
#   - manager  (workspace admin, e.g. Lora) — can flip the toggle
#   - member   (non-manager workspace member, role "editor") — cannot flip
#   - outsider (signed-in user with no NYK membership) — cannot flip
class GroceryPriceToggleTest < ActionDispatch::IntegrationTest
  setup do
    @manager  = User.create!(email_address: "groc-mgr-#{SecureRandom.hex(4)}@example.com", role: "user")
    @member   = User.create!(email_address: "groc-mem-#{SecureRandom.hex(4)}@example.com", role: "user")
    @outsider = User.create!(email_address: "groc-out-#{SecureRandom.hex(4)}@example.com", role: "user")

    @nyk = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @manager }
    @nyk.memberships.find_or_create_by!(user: @manager) { |m| m.role = "admin" }
    @nyk.memberships.find_or_create_by!(user: @member)  { |m| m.role = "editor" }
    @nyk.update!(show_grocery_prices: false)
  end

  test "defaults off" do
    refute @nyk.reload.show_grocery_prices?
  end

  test "a workspace manager can flip the toggle on and back off" do
    sign_in_as(@manager)
    post toggle_grocery_prices_workspace_path(@nyk.slug)
    assert @nyk.reload.show_grocery_prices?, "manager should be able to turn estimates on"

    post toggle_grocery_prices_workspace_path(@nyk.slug)
    refute @nyk.reload.show_grocery_prices?, "manager should be able to turn estimates off"
  end

  test "a non-manager member cannot flip the toggle" do
    sign_in_as(@member)
    post toggle_grocery_prices_workspace_path(@nyk.slug)
    refute @nyk.reload.show_grocery_prices?, "editor should not be able to flip the toggle"
  end

  test "an outsider cannot flip the toggle" do
    sign_in_as(@outsider)
    post toggle_grocery_prices_workspace_path(@nyk.slug)
    refute @nyk.reload.show_grocery_prices?, "non-member should not be able to flip the toggle"
  end

  test "the manager sees the toggle control on the NYK hub; a member does not" do
    sign_in_as(@manager)
    get nykitchen_path
    assert_response :success
    assert_match "Show grocery price estimates", response.body

    sign_in_as(@member)
    get nykitchen_path
    assert_response :success
    assert_no_match "Show grocery price estimates", response.body
  end
end

require "test_helper"

# Hub cards render in a fixed, curated CSS order: the core three (Sam=list,
# Echo=social, Neon=display) lead — Sam top-left, Echo top-right, Neon below
# Sam — then the background agents. The order no longer floats by usage or pins
# failed agents; it's deterministic for every user.
class KitchenHubCardOrderTest < ActionDispatch::IntegrationTest
  DEFAULT = KitchenController::HUB_CARD_DEFAULT_ORDER

  setup do
    @user = User.create!(email_address: "hub-#{SecureRandom.hex(4)}@example.com", role: "user")
  end

  test "the core three lead: Sam, Echo, Neon" do
    assert_equal %w[list social display], DEFAULT.first(3)
    get "/nykitchen"
    assert_response :success
    order = assigns_card_order
    assert_equal 0, order["list"],    "Sam is first (top-left)"
    assert_equal 1, order["social"],  "Echo is second (top-right)"
    assert_equal 2, order["display"], "Neon is third (below Sam)"
  end

  test "the order is fixed regardless of usage" do
    sign_in_as(@user)
    5.times { PageView.create!(path: "/nykitchen/test", session_id: "s1", user_id: @user.id) }
    get "/nykitchen"
    assert_equal DEFAULT.each_with_index.to_h, assigns_card_order, "usage does not reshuffle the board"
  end

  test "a failed agent keeps its place (its red dot still shows there)" do
    controller = KitchenController.new
    controller.instance_variable_set(:@hub_agent_status, { display: :failed })
    order = controller.send(:hub_card_order)
    assert_equal DEFAULT.each_with_index.to_h, order
    assert_equal 2, order["display"], "a failed Neon stays in position, not pinned to top"
  end

  test "the field roster shows the workspace member avatars under the header" do
    admin  = User.create!(email_address: "hubadmin-#{SecureRandom.hex(4)}@example.com", role: "admin")
    ws     = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = admin }
    member = User.create!(email_address: "hubmember-#{SecureRandom.hex(4)}@example.com")
    ws.memberships.find_or_create_by!(user: member) { |m| m.role = "editor" }

    sign_in_as(admin)
    get "/nykitchen"
    assert_response :success
    # The overlapping member-avatar stack (workspaces/_member_avatars) root.
    assert_includes @response.body, "flex -space-x-2 shrink-0",
                    "expected the member avatar stack on the Field Roster header"
  end

  private

  def assigns_card_order
    @controller.view_assigns["hub_card_order"]
  end
end

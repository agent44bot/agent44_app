require "test_helper"

# Hub cards self-organize: per-user 30-day PageView frequency decides the CSS
# order, failed agents jump the queue, anonymous viewers get the default
# layout, and the ranking is cached per user per day so it's stable.
class KitchenHubCardOrderTest < ActionDispatch::IntegrationTest
  DEFAULT = KitchenController::HUB_CARD_DEFAULT_ORDER

  setup do
    Rails.cache.clear
    @user = User.create!(email_address: "hub-#{SecureRandom.hex(4)}@example.com", role: "user")
  end

  test "anonymous viewer gets the default card order" do
    get "/nykitchen"
    assert_response :success
    order = assigns_card_order
    assert_equal DEFAULT.each_with_index.to_h.values, DEFAULT.map { |k| order[k] }
  end

  test "most-visited agent page rises to the top for the signed-in user" do
    sign_in_as(@user)
    3.times { |i| PageView.create!(path: "/nykitchen/test", session_id: "s1", user_id: @user.id) }
    PageView.create!(path: "/nykitchen/analyst", session_id: "s1", user_id: @user.id)

    get "/nykitchen"
    assert_response :success
    order = assigns_card_order
    assert_equal 0, order["test"], "most-visited card should be first"
    assert_equal 1, order["analyst"]
    # Unvisited cards keep their relative default order after the visited ones.
    rest = DEFAULT - %w[test analyst]
    assert_equal rest, order.reject { |k, _| %w[test analyst].include?(k) }.sort_by { |_, v| v }.map(&:first)
  end

  test "old visits outside the 30-day window do not count" do
    sign_in_as(@user)
    5.times { PageView.create!(path: "/nykitchen/ask", session_id: "s1", user_id: @user.id, created_at: 45.days.ago) }

    get "/nykitchen"
    order = assigns_card_order
    assert_equal DEFAULT.index("ask"), order["ask"], "stale visits should not move the card"
  end

  test "ranking is cached for the day" do
    # Test env uses :null_store, which never caches; swap in a real store so
    # the daily-stability behavior is actually exercised.
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    sign_in_as(@user)
    get "/nykitchen"
    first_order = assigns_card_order

    # New views after the first render must not reshuffle today's layout.
    4.times { PageView.create!(path: "/nykitchen/data", session_id: "s1", user_id: @user.id) }
    get "/nykitchen"
    assert_equal first_order, assigns_card_order
  ensure
    Rails.cache = original_cache
  end

  test "failed agents jump the queue ahead of the frequency order" do
    controller = KitchenController.new
    controller.instance_variable_set(:@hub_agent_status, { display: :failed, list: :on_cadence })
    order = controller.send(:hub_card_order)
    assert_equal 0, order["display"], "failed agent should be pinned first"
    # Everyone else keeps the default relative order behind it.
    rest = DEFAULT - %w[display]
    assert_equal rest, order.reject { |k, _| k == "display" }.sort_by { |_, v| v }.map(&:first)
  end

  private

  # The controller exposes kind => CSS order; read it off the rendered page
  # by parsing the inline order: declarations is brittle, so reach into the
  # controller's assigns instead.
  def assigns_card_order
    @controller.view_assigns["hub_card_order"]
  end
end

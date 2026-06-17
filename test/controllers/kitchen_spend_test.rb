require "test_helper"

# /nykitchen/spend — the owner/admin-only AI spend monitor for the two paid
# Opus features (grocery list + recipe generation). Read-only rollup over
# AiCallLog; access is gated to NYK managers (Lora + site admins).
class KitchenSpendTest < ActionDispatch::IntegrationTest
  setup do
    @ws = Workspace.find_by(slug: "nykitchen") || begin
      owner = User.create!(email_address: "ws-owner-#{SecureRandom.hex(4)}@example.com", role: "user")
      Workspace.create!(slug: "nykitchen", name: "NY Kitchen", owner: owner)
    end
  end

  def log(source, model: "claude-opus-4-8", input: 1_000, output: 2_000, at: Time.current)
    AiCallLog.create!(source: source, model: model, input_tokens: input, output_tokens: output, created_at: at)
  end

  test "site admin sees the page with both functions and the month total" do
    sign_in_as(User.create!(email_address: "admin-#{SecureRandom.hex(4)}@example.com", role: "admin"))
    log("nyk_grocery_list", input: 2_000, output: 4_000)
    log("nyk_recipe_extract", input: 1_000, output: 1_000)

    get nyk_spend_path
    assert_response :success
    assert_match "AI spend", response.body
    assert_match "Grocery lists", response.body
    assert_match "Recipe generation", response.body
    # Grocery: 2k in * $5/M + 4k out * $25/M = $0.01 + $0.10 = $0.11
    assert_match "$0.11", response.body
  end

  test "workspace owner (Lora) sees the page" do
    owner = User.create!(email_address: "owner-#{SecureRandom.hex(4)}@example.com", role: "user")
    @ws.memberships.create!(user: owner, role: "owner")
    sign_in_as(owner)

    get nyk_spend_path
    assert_response :success
    assert_match "AI spend", response.body
  end

  test "editor/viewer members are denied (404)" do
    editor = User.create!(email_address: "editor-#{SecureRandom.hex(4)}@example.com", role: "user")
    @ws.memberships.create!(user: editor, role: "editor")
    sign_in_as(editor)

    get nyk_spend_path
    assert_response :not_found
  end

  test "a signed-in non-member is denied (404)" do
    sign_in_as(User.create!(email_address: "rando-#{SecureRandom.hex(4)}@example.com", role: "user"))
    get nyk_spend_path
    assert_response :not_found
  end

  test "only the two spend sources are counted, not other AI usage" do
    sign_in_as(User.create!(email_address: "admin2-#{SecureRandom.hex(4)}@example.com", role: "admin"))
    log("nyk_grocery_list", input: 2_000, output: 4_000)  # $0.11
    log("nyk_ask", input: 1_000_000, output: 1_000_000)   # huge, but must be excluded

    get nyk_spend_path
    assert_response :success
    # Month headline total = grocery only ($0.11); the unrelated nyk_ask call is ignored.
    assert_match "$0.11", response.body
    assert_no_match(/\$5\.00|\$6\.00|\$30\.00/, response.body)
  end
end

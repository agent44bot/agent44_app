require "test_helper"

# The hub's Super Agent "morning question" card is gated to the single trial
# user named in the kv setting super_agent_daily_prompt_email.
class KitchenMorningPromptTest < ActionDispatch::IntegrationTest
  setup do
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    snap.kitchen_events.create!(url: "https://nykitchen.test/a", name: "Risotto Workshop",
                                availability: "InStock", spots_left: 1, start_at: 2.days.from_now)
  end

  teardown { Setting.delete_key("super_agent_daily_prompt_email") }

  test "the trial user sees the morning question wired to auto-ask" do
    user = User.create!(email_address: "trial-#{SecureRandom.hex(4)}@example.com", role: "admin")
    Setting.set("super_agent_daily_prompt_email", user.email_address)
    sign_in_as(user)

    get "/nykitchen"
    assert_response :success
    assert_match(/(This (morning|afternoon|evening)|Tonight):/, @response.body)
    assert_match "Risotto Workshop", @response.body
    # The question chip links to the ask page with the prompt prefilled + auto-send,
    assert_match(/\/nykitchen\/ask\?[^"']*q=/, @response.body)
    assert_match(/go=1/, @response.body)
    # …and the card body still offers a plain "open a fresh chat" link (no prompt).
    assert_match %r{href="/nykitchen/ask"}, @response.body
  end

  test "a non-trial user sees the plain static card" do
    Setting.set("super_agent_daily_prompt_email", "someone-else@example.com")
    sign_in_as(User.create!(email_address: "other-#{SecureRandom.hex(4)}@example.com", role: "admin"))

    get "/nykitchen"
    assert_response :success
    assert_no_match(/(This (morning|afternoon|evening)|Tonight):/, @response.body)
    assert_match "What sold out this week?", @response.body
  end

  test "with the setting unset, nobody sees the morning question" do
    sign_in_as(User.create!(email_address: "noone-#{SecureRandom.hex(4)}@example.com", role: "admin"))

    get "/nykitchen"
    assert_response :success
    assert_no_match(/(This (morning|afternoon|evening)|Tonight):/, @response.body)
  end
end

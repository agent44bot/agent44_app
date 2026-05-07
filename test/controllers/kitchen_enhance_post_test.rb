require "test_helper"
require "ostruct"
require "minitest/mock"

# Verifies that /nykitchen/enhance_post writes an ai_call_logs row when an
# Anthropic call succeeds. Per the project rule "No AI enhance in tests" —
# Anthropic::Client is fully stubbed; nothing reaches the real API.
class KitchenEnhancePostTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "kitchen-enhance-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(@user)
    ENV["ANTHROPIC_API_KEY"] = "test-key"
  end

  teardown { ENV.delete("ANTHROPIC_API_KEY") }

  test "writes an ai_call_logs row attributed to the signed-in user" do
    text_block = OpenStruct.new(text: "Enhanced post text!")
    fake_response = OpenStruct.new(
      content: [text_block],
      usage:   OpenStruct.new(input_tokens: 1234, output_tokens: 567)
    )
    fake_messages = OpenStruct.new
    fake_messages.define_singleton_method(:create) { |**| fake_response }
    fake_client = OpenStruct.new(messages: fake_messages)

    Anthropic::Client.stub :new, ->(**) { fake_client } do
      assert_difference -> { AiCallLog.count }, 1 do
        post "/nykitchen/enhance_post",
          params: { event_url: "https://nykitchen.com/event/test/", draft: "Class draft", event_name: "Test", event_description: "desc", event_date: "2026-06-01", event_price: "50" }
      end
    end

    assert_response :success
    log = AiCallLog.last
    assert_equal "claude-haiku-4-5-20251001", log.model
    assert_equal "nyk_enhance",                log.source
    assert_equal 1234, log.input_tokens
    assert_equal 567,  log.output_tokens
    assert_equal @user.id, log.user_id
  end

  test "missing API key short-circuits without creating a log row" do
    ENV.delete("ANTHROPIC_API_KEY")

    assert_no_difference -> { AiCallLog.count } do
      post "/nykitchen/enhance_post",
        params: { event_url: "https://nykitchen.com/event/test/", draft: "x", event_name: "x", event_description: "x", event_date: "x", event_price: "0" }
    end

    assert_response :unprocessable_entity
  end
end

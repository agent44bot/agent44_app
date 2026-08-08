require "test_helper"
require "minitest/mock"

class Api::V1::TelegramWebhookControllerTest < ActionDispatch::IntegrationTest
  SECRET = "test-telegram-webhook-secret"
  OWNER_CHAT = "7349915265"

  setup do
    ENV["TELEGRAM_WEBHOOK_SECRET"] = SECRET
    ENV["TELEGRAM_CHAT_ID"] = OWNER_CHAT
    # Deliberately no TELEGRAM_BOT_TOKEN: keeps TelegramNotifier from trying to
    # call the Telegram API during these tests.
  end

  teardown do
    ENV.delete("TELEGRAM_WEBHOOK_SECRET")
    ENV.delete("TELEGRAM_CHAT_ID")
  end

  test "rejects an update with no secret token" do
    post "/api/v1/telegram/webhook",
      params: update(text: "deploy agent44").to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
    assert_equal 0, AgentMessage.where(content: "deploy:agent44-app").count
  end

  test "rejects an update with the wrong secret token" do
    post "/api/v1/telegram/webhook",
      params: update(text: "deploy agent44").to_json,
      headers: headers(secret: "not-the-secret")

    assert_response :unauthorized
    assert_equal 0, AgentMessage.where(content: "deploy:agent44-app").count
  end

  test "queues a deploy for the owner chat with the right secret token" do
    assert_difference -> { AgentMessage.where(content: "deploy:agent44-app").count }, 1 do
      post "/api/v1/telegram/webhook",
        params: update(text: "deploy agent44").to_json,
        headers: headers
    end

    assert_response :success
    assert_equal "busy", agents(:knox).reload.status
  end

  test "ignores a deploy command from another chat" do
    assert_no_difference -> { AgentMessage.count } do
      post "/api/v1/telegram/webhook",
        params: update(text: "deploy agent44", chat_id: "999000111").to_json,
        headers: headers
    end

    assert_response :success
    assert_equal "online", agents(:knox).reload.status
  end

  test "ignores a smoke command from another chat" do
    triggered = false
    SmokeDispatch.stub(:trigger!, ->(**) { triggered = true }) do
      post "/api/v1/telegram/webhook",
        params: update(text: "/smoke_nyk", chat_id: "999000111").to_json,
        headers: headers
    end

    assert_response :success
    assert_not triggered
  end

  test "runs a smoke command from the owner chat" do
    triggered = false
    SmokeDispatch.stub(:trigger!, ->(**) { triggered = true }) do
      post "/api/v1/telegram/webhook",
        params: update(text: "/smoke_nyk").to_json,
        headers: headers
    end

    assert_response :success
    assert triggered
  end

  test "still tracks agent status from bot messages" do
    post "/api/v1/telegram/webhook",
      params: update(text: "Russ is scanning the repo", is_bot: true).to_json,
      headers: headers

    assert_response :success
    assert_equal "busy", agents(:russ).reload.status
  end

  private

  def headers(secret: SECRET)
    { "Content-Type" => "application/json", "X-Telegram-Bot-Api-Secret-Token" => secret }
  end

  def update(text:, chat_id: OWNER_CHAT, is_bot: false)
    {
      message: {
        text: text,
        chat: { id: chat_id },
        from: { first_name: "Rich", is_bot: is_bot }
      }
    }
  end
end

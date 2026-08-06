require "test_helper"

class Api::V1::TelegramWebhookControllerTest < ActionDispatch::IntegrationTest
  def bot_says(text)
    post "/api/v1/telegram/webhook", params: {
      message: { text: text, from: { is_bot: true, first_name: "Ripley" } }
    }, as: :json
  end

  test "seeded agent goes busy when the bot reports it working" do
    bot_says("Vlad is running the smoke suite")

    assert_response :success
    vlad = agents(:vlad).reload
    assert_equal "busy", vlad.status
    assert vlad.last_active_at.present?
  end

  test "an agent added after the seed roster also checks in" do
    fizz = Agent.create!(name: "Fizz", role: "Bug Fixer", avatar_color: "green",
                         status: "online", position: 8)
    assert_equal "fizz", fizz.slug

    bot_says("Fizz is working on the calendar regression")

    assert_response :success
    assert_equal "busy", fizz.reload.status
    assert fizz.last_active_at.present?
  end

  test "an unknown name leaves every agent alone" do
    bot_says("Gizmo is scanning the repo")

    assert_response :success
    assert_equal [], Agent.where(status: "busy").pluck(:name)
  end

  test "a finished report clears the current task" do
    agents(:knox).update!(status: "busy", current_task: "Deploying agent44-app",
                          last_active_at: Time.current)

    bot_says("Knox has finished")

    assert_response :success
    knox = agents(:knox).reload
    assert_equal "online", knox.status
    assert_nil knox.current_task
  end
end

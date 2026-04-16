require "test_helper"
require "active_support/testing/method_call_assertions"

class Api::V1::AgentsControllerTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::MethodCallAssertions

  setup do
    @token = Rails.application.credentials.api_token || ENV["API_TOKEN"]
    @headers = { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" }
  end

  test "GET statuses returns all agents in order" do
    get "/api/v1/agents/statuses"
    assert_response :success

    agents = JSON.parse(response.body)
    assert_equal 7, agents.length
    assert_equal "Ripley", agents.first["name"]
    agents.each do |a|
      assert a.key?("name")
      assert a.key?("status")
      assert a.key?("task")
      assert a.key?("role")
    end
  end

  test "GET statuses returns busy agents first" do
    agents(:russ).update!(status: "busy", current_task: "Scanning", last_active_at: Time.current)

    get "/api/v1/agents/statuses"
    agents = JSON.parse(response.body)
    assert_equal "Russ 🔒", agents.first["name"]
    assert_equal "busy", agents.first["status"]
  end

  test "PATCH update_status requires auth" do
    patch "/api/v1/agents/Ripley/status",
      params: { status: "busy" }.to_json,
      headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  test "PATCH update_status sets agent to busy" do
    patch "/api/v1/agents/Ripley/status",
      params: { status: "busy", current_task: "Coordinating scan" }.to_json,
      headers: @headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "busy", body["status"]
    assert_equal "Coordinating scan", body["current_task"]

    agents(:ripley).reload
    assert agents(:ripley).busy?
    assert_equal "Coordinating scan", agents(:ripley).current_task
    assert_not_nil agents(:ripley).last_active_at
  end

  test "PATCH update_status sets agent back to online" do
    agents(:russ).update!(status: "busy", current_task: "Scanning")

    patch "/api/v1/agents/#{URI::DEFAULT_PARSER.escape('Russ 🔒')}/status",
      params: { status: "online", current_task: nil }.to_json,
      headers: @headers
    assert_response :success

    agents(:russ).reload
    assert agents(:russ).online?
  end

  test "PATCH update_status returns 404 for unknown agent" do
    patch "/api/v1/agents/Nobody/status",
      params: { status: "busy" }.to_json,
      headers: @headers
    assert_response :not_found
  end

  test "PATCH update_status rejects invalid status" do
    patch "/api/v1/agents/Ripley/status",
      params: { status: "dancing" }.to_json,
      headers: @headers
    assert_response :unprocessable_entity
  end

  test "busy agent appears at top of statuses list" do
    # Scout is position 7 (last)
    agents(:scout).update!(status: "busy", current_task: "Research", last_active_at: Time.current)

    get "/api/v1/agents/statuses"
    agents = JSON.parse(response.body)
    assert_equal "Scout 🔭", agents.first["name"]
    assert_equal "busy", agents.first["status"]
    assert_equal "Research", agents.first["task"]
  end

  test "multiple busy agents appear before online agents" do
    agents(:russ).update!(status: "busy", current_task: "Scanning", last_active_at: Time.current)
    agents(:vlad).update!(status: "busy", current_task: "Testing", last_active_at: 1.second.ago)

    get "/api/v1/agents/statuses"
    agents_list = JSON.parse(response.body)
    busy_names = agents_list.select { |a| a["status"] == "busy" }.map { |a| a["name"] }
    online_names = agents_list.select { |a| a["status"] == "online" }.map { |a| a["name"] }

    # All busy agents should come before all online agents
    last_busy_idx = agents_list.index { |a| a["name"] == busy_names.last }
    first_online_idx = agents_list.index { |a| a["name"] == online_names.first }
    assert last_busy_idx < first_online_idx, "All busy agents should be above all online agents"
  end

  # --- Ripley unmute regression guard ---
  # Commit 84122ba removed the Ripley-specific Telegram skip in notify_status_change.
  # These tests ensure status transitions actually reach TelegramNotifier.

  test "PATCH online → busy on Ripley fires Telegram alert" do
    assert_called(TelegramNotifier, :send_alert, times: 1) do
      patch "/api/v1/agents/Ripley/status",
        params: { status: "busy", current_task: "Coordinating smoke test" }.to_json,
        headers: @headers
      assert_response :success
    end

    note = Notification.where(source: "agent_status").order(created_at: :desc).first
    assert_equal "Ripley is now working",   note.title
    assert_equal "Coordinating smoke test", note.body
    assert_equal "info",                    note.level
  end

  test "PATCH busy → online on Ripley fires 'finished task' Telegram alert" do
    agents(:ripley).update!(status: "busy", current_task: "Orchestrating")

    assert_called(TelegramNotifier, :send_alert, times: 1) do
      patch "/api/v1/agents/Ripley/status",
        params: { status: "online", current_task: nil }.to_json,
        headers: @headers
      assert_response :success
    end

    note = Notification.where(source: "agent_status").order(created_at: :desc).first
    assert_equal "Ripley finished task", note.title
    assert_equal "success",              note.level
  end

  test "PATCH with unchanged status does not fire Telegram" do
    assert_not_called(TelegramNotifier, :send_alert) do
      patch "/api/v1/agents/Ripley/status",
        params: { status: "online" }.to_json,
        headers: @headers
      assert_response :success
    end
  end
end

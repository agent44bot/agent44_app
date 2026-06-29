require "test_helper"
require "ostruct"

class WorkspaceModelToggleTest < ActionDispatch::IntegrationTest
  setup do
    @owner  = User.create!(email_address: "mt-o-#{SecureRandom.hex(4)}@example.com")
    @editor = User.create!(email_address: "mt-e-#{SecureRandom.hex(4)}@example.com")
    @ws  = Workspace.create!(name: "Toggle WS", description: "Greens.", owner: @owner)
    @ws2 = Workspace.create!(name: "Other WS", owner: @owner)
    @ws.memberships.create!(user: @editor, role: "editor")
  end

  test "ModelChoice defaults to haiku and is per-workspace" do
    assert_equal "haiku", WorkspaceAi::ModelChoice.selected_key(@ws, "connect_help_chat")
    assert_equal "claude-haiku-4-5-20251001",
                 WorkspaceAi::ModelChoice.resolve(@ws, "connect_help_chat", default: "claude-haiku-4-5-20251001")

    WorkspaceAi::ModelChoice.set(@ws, "connect_help_chat", "opus")
    assert_equal "opus", WorkspaceAi::ModelChoice.selected_key(@ws, "connect_help_chat")
    assert_equal "claude-opus-4-8",
                 WorkspaceAi::ModelChoice.resolve(@ws, "connect_help_chat", default: "claude-haiku-4-5-20251001")
    # Other workspace is unaffected.
    assert_equal "haiku", WorkspaceAi::ModelChoice.selected_key(@ws2, "connect_help_chat")
  end

  test "owner can change a feature's model; it persists" do
    sign_in_as(@owner)
    post billing_model_workspace_path(@ws.slug), params: { feature: "workspace_ai_assist", model: "sonnet" }
    assert_redirected_to billing_workspace_path(@ws.slug)
    assert_equal "sonnet", WorkspaceAi::ModelChoice.selected_key(@ws, "workspace_ai_assist")
  end

  test "unknown feature or model is rejected" do
    sign_in_as(@owner)
    post billing_model_workspace_path(@ws.slug), params: { feature: "workspace_ai_assist", model: "gpt" }
    assert_equal "haiku", WorkspaceAi::ModelChoice.selected_key(@ws, "workspace_ai_assist")
    post billing_model_workspace_path(@ws.slug), params: { feature: "nope", model: "opus" }
    assert_response :redirect
  end

  test "editor (non-manager) cannot change the model" do
    sign_in_as(@editor)
    post billing_model_workspace_path(@ws.slug), params: { feature: "workspace_ai_assist", model: "opus" }
    assert_redirected_to workspace_path(@ws.slug)
    assert_equal "haiku", WorkspaceAi::ModelChoice.selected_key(@ws, "workspace_ai_assist")
  end

  test "Drafter uses the selected model and logs it" do
    ENV["ANTHROPIC_API_KEY"] = "stub"
    WorkspaceAi::ModelChoice.set(@ws, "workspace_ai_assist", "opus")
    WorkspaceAi::Drafter.stub = ->(_prompt) {
      OpenStruct.new(content: [ OpenStruct.new(text: "fresh microgreens today") ],
                     usage: OpenStruct.new(input_tokens: 100, output_tokens: 30))
    }
    WorkspaceAi::Drafter.new(@ws, user: @owner).suggest(topic: "hi")
    assert_equal "claude-opus-4-8", AiCallLog.where(source: "workspace_ai_assist").last.model
  ensure
    WorkspaceAi::Drafter.stub = nil
    ENV.delete("ANTHROPIC_API_KEY")
  end
end

require "test_helper"
require "ostruct"

class WorkspaceDraftsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "wd-o-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "Drafts WS", description: "Builder energy. No fluff.", owner: @owner)
    @ws.social_accounts.create!(platform: "x", connected_by: @owner, handle: "@magenta", external_id: "1",
      access_token: "AT", refresh_token: "RT", token_expires_at: 2.hours.from_now, status: "active")

    @captured_prompt = nil
    WorkspaceAi::Drafter.stub = ->(prompt) {
      @captured_prompt = prompt
      OpenStruct.new(
        content: [OpenStruct.new(text: "shipped: tokens encrypted at rest #builder")],
        usage:   OpenStruct.new(input_tokens: 120, output_tokens: 60)
      )
    }
  end

  teardown { WorkspaceAi::Drafter.stub = nil }

  test "suggest persists flash[:draft_text], renders pre-filled textarea, logs usage" do
    ENV["ANTHROPIC_API_KEY"] = "stub"
    sign_in_as(@owner)

    assert_difference -> { AiCallLog.where(source: "workspace_ai_assist").count }, 1 do
      post workspace_draft_suggest_path(workspace_slug: @ws.slug), params: { topic: "tokens at rest" }
    end
    assert_redirected_to workspace_path(@ws.slug)
    assert_match "tokens at rest", @captured_prompt
    assert_match "Builder energy", @captured_prompt

    follow_redirect!
    assert_match "shipped: tokens encrypted at rest #builder", response.body
    assert_match "AI-suggested", response.body
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
  end

  test "credentials fallback: works when ENV is blank but credentials.anthropic.api_key is set" do
    ENV.delete("ANTHROPIC_API_KEY")
    with_credentials_dig("creds-key") do
      sign_in_as(@owner)
      post workspace_draft_suggest_path(workspace_slug: @ws.slug), params: { topic: "x" }
    end
    assert_redirected_to workspace_path(@ws.slug)
    assert_match /Draft suggestion ready/, flash[:notice]
  end

  test "missing API key (both blank) returns alert without calling the AI" do
    ENV.delete("ANTHROPIC_API_KEY")
    WorkspaceAi::Drafter.stub = ->(_prompt) { raise "should not have called AI" }

    with_credentials_dig(nil) do
      sign_in_as(@owner)
      post workspace_draft_suggest_path(workspace_slug: @ws.slug), params: { topic: "x" }
    end
    assert_match /AI assist failed/, flash[:alert]
    assert_match /not set/i, flash[:alert]
  end


  test "AI error surfaces as alert" do
    ENV["ANTHROPIC_API_KEY"] = "stub"
    WorkspaceAi::Drafter.stub = ->(_prompt) { raise "API down" }
    sign_in_as(@owner)
    post workspace_draft_suggest_path(workspace_slug: @ws.slug), params: { topic: "x" }
    assert_match /AI assist failed/, flash[:alert]
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
  end
end

require "test_helper"
require "ostruct"

class WorkspaceDraftsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "wd-o-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @ws    = Workspace.create!(name: "Drafts WS", description: "Builder energy. No fluff.", owner: @owner)
    @ws.social_accounts.create!(platform: "x", connected_by: @owner, handle: "@magenta", external_id: "1",
      access_token: "AT", refresh_token: "RT", token_expires_at: 2.hours.from_now, status: "active")

    @captured_prompt = nil
    WorkspaceAi::Drafter.stub = ->(prompt) {
      @captured_prompt = prompt
      OpenStruct.new(
        content: [ OpenStruct.new(text: "shipped: tokens encrypted at rest #builder") ],
        usage:   OpenStruct.new(input_tokens: 120, output_tokens: 60)
      )
    }
  end

  teardown { WorkspaceAi::Drafter.stub = nil }

  test "URLs in the existing draft are forced into the prompt as preserve-verbatim constraints" do
    ENV["ANTHROPIC_API_KEY"] = "stub"
    sign_in_as(@owner)
    post workspace_draft_suggest_path(workspace_slug: @ws.slug),
         params: { topic: "Shorten for X", body: "Long NYK promo — register at https://nykitchen.com/event/x and see https://nykitchen.com/classes for the full list" }
    assert_match "MUST preserve these URLs verbatim", @captured_prompt
    assert_match "https://nykitchen.com/event/x", @captured_prompt
    assert_match "https://nykitchen.com/classes", @captured_prompt
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
  end

  test "suggest persists flash[:draft_text], renders pre-filled textarea, logs usage" do
    ENV["ANTHROPIC_API_KEY"] = "stub"
    sign_in_as(@owner)

    assert_difference -> { AiCallLog.where(source: "workspace_ai_assist").count }, 1 do
      post workspace_draft_suggest_path(workspace_slug: @ws.slug), params: { topic: "tokens at rest" }
    end
    assert_redirected_to social_workspace_path(@ws.slug)
    assert_equal @ws.id, AiCallLog.where(source: "workspace_ai_assist").last.workspace_id, "draft usage is attributed to the workspace"
    assert_match "tokens at rest", @captured_prompt
    assert_match "Builder energy", @captured_prompt

    follow_redirect!
    assert_match "shipped: tokens encrypted at rest #builder", response.body
    assert_match "AI-suggested", response.body
    # The composer must be OPEN (not collapsed) so the suggested draft is visible.
    assert_no_match(/data-composer-target="body" class="[^"]*hidden/, response.body)
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
  end

  test "composer is always visible (it lives in the New post tab, no collapse)" do
    sign_in_as(@owner)
    get social_workspace_path(@ws.slug)
    assert_response :success
    # The composer no longer collapses; it is a tab panel, shown when the New
    # post tab is active (echo_tabs_controller), never hidden inline.
    assert_no_match(/data-composer-target="body" class="[^"]*hidden/, response.body)
    assert_match(/data-echo-tabs-target="panel" data-tab="newpost"/, response.body)
  end

  test "credentials fallback: works when ENV is blank but credentials.anthropic.api_key is set" do
    ENV.delete("ANTHROPIC_API_KEY")
    with_credentials_dig("creds-key") do
      sign_in_as(@owner)
      post workspace_draft_suggest_path(workspace_slug: @ws.slug), params: { topic: "x" }
    end
    assert_redirected_to social_workspace_path(@ws.slug)
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

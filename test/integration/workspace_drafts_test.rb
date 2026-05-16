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
        content: [OpenStruct.new(text: "shipped: tokens encrypted at rest #builder")],
        usage:   OpenStruct.new(input_tokens: 120, output_tokens: 60)
      )
    }
  end

  teardown do
    WorkspaceAi::Drafter.stub = nil
    WorkspaceAi::Drafter.site_fetch_stub = nil
  end

  test "mode=site fetches the workspace source_url and folds it into the prompt" do
    @ws.update!(source_url: "https://nykitchen.com")
    ENV["ANTHROPIC_API_KEY"] = "stub"
    WorkspaceAi::Drafter.site_fetch_stub = ->(url) {
      assert_equal "https://nykitchen.com", url
      "<html><body>Sushi Rolling Class with Mor — Sat 5/16 11am, 23 of 24 sold</body></html>"
    }

    sign_in_as(@owner)
    post workspace_draft_suggest_path(workspace_slug: @ws.slug), params: { mode: "site" }
    assert_redirected_to workspace_path(@ws.slug)
    assert_match "Live content scraped from https://nykitchen.com", @captured_prompt
    assert_match "Sushi Rolling Class with Mor", @captured_prompt
    assert_nothing_raised { follow_redirect! }
    assert_match /Drafted from https:\/\/nykitchen.com/, response.body
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
  end

  test "mode=site without a source_url falls through to topic-mode prompt" do
    ENV["ANTHROPIC_API_KEY"] = "stub"
    sign_in_as(@owner)
    post workspace_draft_suggest_path(workspace_slug: @ws.slug), params: { mode: "site", topic: "fallback" }
    assert_redirected_to workspace_path(@ws.slug)
    refute_match "Live content scraped from", @captured_prompt
    assert_match "fallback", @captured_prompt
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
  end

  test "mode=site reports an error when the fetch fails" do
    @ws.update!(source_url: "https://nykitchen.com")
    ENV["ANTHROPIC_API_KEY"] = "stub"
    WorkspaceAi::Drafter.site_fetch_stub = ->(_url) { nil } # nil → fetch failed
    WorkspaceAi::Drafter.stub = ->(_p) { raise "should not have called AI" }

    sign_in_as(@owner)
    post workspace_draft_suggest_path(workspace_slug: @ws.slug), params: { mode: "site" }
    assert_match /Could not fetch/, flash[:alert]
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
  end

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

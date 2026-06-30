require "test_helper"
require "ostruct"

class WorkspaceAiChatTest < ActionDispatch::IntegrationTest
  setup do
    @owner   = User.create!(email_address: "chat-o-#{SecureRandom.hex(4)}@example.com")
    @wsadmin = User.create!(email_address: "chat-a-#{SecureRandom.hex(4)}@example.com")
    @editor  = User.create!(email_address: "chat-e-#{SecureRandom.hex(4)}@example.com")
    @outsider = User.create!(email_address: "chat-x-#{SecureRandom.hex(4)}@example.com")
    @ws = Workspace.create!(name: "Chat WS", description: "Microgreens, family run.",
                            owner: @owner, usage_multiplier: 5.0)
    @ws.memberships.create!(user: @wsadmin, role: "admin")
    @ws.memberships.create!(user: @editor, role: "editor")

    @captured = nil
    WorkspaceAi::ConnectHelper.stub = ->(system:, messages:) {
      @captured = { system: system, messages: messages }
      OpenStruct.new(
        content: [ OpenStruct.new(text: "Press Connect, then log in to Facebook and pick your Page.") ],
        usage:   OpenStruct.new(input_tokens: 200, output_tokens: 50)
      )
    }
  end

  teardown { WorkspaceAi::ConnectHelper.stub = nil }

  test "owner sees raw + billed (x multiplier), logged to the workspace + user" do
    ENV["ANTHROPIC_API_KEY"] = "stub"
    sign_in_as(@owner)

    assert_difference -> { AiCallLog.where(source: "connect_help_chat").count }, 1 do
      post workspace_ai_chat_path(workspace_slug: @ws.slug),
           params: { platform: "facebook", message: "How do I connect my Facebook Page?" }, as: :json
    end
    assert_response :success
    body = JSON.parse(response.body)
    assert body["ok"]
    assert_match "log in to Facebook", body["reply"]
    assert body.key?("month_raw"),   "owner should see raw cost"
    assert body.key?("month_billed"), "owner should see billed cost"
    assert_equal 5.0, body["multiplier"]
    assert_in_delta body["month_raw"] * 5.0, body["month_billed"], 1e-9, "billed = raw x multiplier"

    log = AiCallLog.where(source: "connect_help_chat").last
    assert_equal @ws.id, log.workspace_id, "cost attributed to the workspace"
    assert_equal @owner.id, log.user_id, "cost attributed to the user"
    assert_match "facebook", @captured[:system].downcase
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
  end

  test "admin (client) sees billed only, never raw" do
    ENV["ANTHROPIC_API_KEY"] = "stub"
    sign_in_as(@wsadmin)

    post workspace_ai_chat_path(workspace_slug: @ws.slug),
         params: { platform: "bluesky", message: "Where is the app password?" }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert body["ok"]
    assert body.key?("month_billed"), "admin should see billed cost"
    assert_not body.key?("month_raw"), "admin must never see raw cost"
    assert_not body.key?("multiplier"), "admin must not see the multiplier"
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
  end

  test "editor (client staff) gets a reply but no cost at all" do
    ENV["ANTHROPIC_API_KEY"] = "stub"
    sign_in_as(@editor)

    post workspace_ai_chat_path(workspace_slug: @ws.slug),
         params: { platform: "bluesky", message: "Where is the app password?" }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert body["ok"]
    assert_not body.key?("month_billed"), "editors see no cost"
    assert_not body.key?("month_raw"), "editors see no cost"
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
  end

  test "the exchange is persisted as a question + reply transcript" do
    ENV["ANTHROPIC_API_KEY"] = "stub"
    sign_in_as(@editor)

    assert_difference -> { ConnectChatMessage.where(workspace: @ws).count }, 2 do
      post workspace_ai_chat_path(workspace_slug: @ws.slug),
           params: { platform: "facebook", message: "How do I connect my Facebook Page?" }, as: :json
    end
    assert_response :success

    q = @ws.connect_chat_messages.chronological.first
    a = @ws.connect_chat_messages.chronological.last
    assert_equal "user", q.role
    assert_equal "How do I connect my Facebook Page?", q.content
    assert_equal @editor.id, q.user_id
    assert_equal "facebook", q.platform
    assert_equal "assistant", a.role
    assert_match "log in to Facebook", a.content
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
  end

  test "only a site admin can review transcripts; workspace owner/admin/editor cannot" do
    @ws.connect_chat_messages.create!(user: @editor, platform: "facebook", role: "user", content: "WHY WONT FACEBOOK CONNECT")
    @ws.connect_chat_messages.create!(user: @editor, platform: "facebook", role: "assistant", content: "Meta setup is pending.")

    site_admin = User.create!(email_address: "site-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    sign_in_as(site_admin)
    get connect_chats_workspace_path(@ws.slug)
    assert_response :success
    assert_match "WHY WONT FACEBOOK CONNECT", response.body
    assert_match "Meta setup is pending.", response.body

    # The workspace owner and admin (clients) must NOT see it.
    [ @owner, @wsadmin, @editor ].each do |client|
      sign_in_as(client)
      get connect_chats_workspace_path(@ws.slug)
      assert_redirected_to social_workspace_path(@ws.slug), "#{client.email_address} should be blocked"
    end
  end

  test "non-members are forbidden" do
    sign_in_as(@outsider)
    post workspace_ai_chat_path(workspace_slug: @ws.slug),
         params: { platform: "x", message: "hi" }, as: :json
    assert_response :forbidden
  end

  test "unknown platform is rejected" do
    sign_in_as(@owner)
    post workspace_ai_chat_path(workspace_slug: @ws.slug),
         params: { platform: "myspace", message: "hi" }, as: :json
    assert_response :unprocessable_entity
  end
end

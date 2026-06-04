require "test_helper"
require "ostruct"

class WorkspaceDraftsCrudTest < ActionDispatch::IntegrationTest
  setup do
    @owner  = User.create!(email_address: "wdc-o-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @viewer = User.create!(email_address: "wdc-v-#{SecureRandom.hex(4)}@example.com")
    @ws     = Workspace.create!(name: "Drafts CRUD WS", owner: @owner, timezone: "Eastern Time (US & Canada)")
    @ws.memberships.create!(user: @viewer, role: "viewer")
    @acct   = @ws.social_accounts.create!(
      platform: "x", connected_by: @owner, handle: "@a44",
      external_id: SecureRandom.hex(4), access_token: "AT", refresh_token: "RT",
      token_expires_at: 2.hours.from_now, status: "active"
    )
  end

  teardown { X::UserClient.http_stub = nil }

  test "save draft (commit=save) creates a draft with status=draft" do
    sign_in_as(@owner)
    assert_difference -> { WorkspaceDraft.count }, 1 do
      post workspace_drafts_path(workspace_slug: @ws.slug),
           params: { body: "save me", target_platforms: [ "x" ], commit: "save" }
    end
    d = WorkspaceDraft.last
    assert_equal "draft", d.status
    assert_nil d.scheduled_for
    assert_redirected_to social_workspace_path(@ws.slug)
  end

  test "schedule (commit=schedule) parses scheduled_for in workspace timezone" do
    sign_in_as(@owner)
    # 9am workspace time tomorrow
    tomorrow = Time.use_zone("Eastern Time (US & Canada)") { 1.day.from_now.change(hour: 9, min: 0).strftime("%Y-%m-%dT%H:%M") }
    post workspace_drafts_path(workspace_slug: @ws.slug),
         params: { body: "schedule me", target_platforms: [ "x" ], commit: "schedule", scheduled_for: tomorrow }
    d = WorkspaceDraft.last
    assert_equal "scheduled", d.status
    assert d.scheduled_for.present?
    assert_equal "EDT", d.scheduled_for.in_time_zone("Eastern Time (US & Canada)").zone
  end

  test "viewer cannot create a draft" do
    sign_in_as(@viewer)
    assert_no_difference -> { WorkspaceDraft.count } do
      post workspace_drafts_path(workspace_slug: @ws.slug),
           params: { body: "no", target_platforms: [ "x" ], commit: "save" }
    end
  end

  test "publish action posts immediately and updates draft status" do
    draft = @ws.workspace_drafts.create!(author: @owner, body: "publish me", target_platforms: %w[x])
    X::UserClient.http_stub = ->(*) { { status: "201", body: { "data" => { "id" => "PUB-1" } } } }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, 1 do
      post publish_workspace_draft_path(workspace_slug: @ws.slug, id: draft.id)
    end
    draft.reload
    assert_equal "published", draft.status
    assert draft.published_at.present?
    assert_equal "PUB-1", WorkspacePost.last.remote_id
  end

  test "publish sets status=partial when one platform fails" do
    @ws.social_accounts.create!(
      platform: "bluesky", connected_by: @owner, handle: "@a44.bsky.social",
      external_id: "did:plc:abc", access_token: "BAT", refresh_token: "BRT", token_secret: "pw",
      token_expires_at: 2.hours.from_now, status: "active"
    )
    draft = @ws.workspace_drafts.create!(author: @owner, body: "mixed", target_platforms: %w[x bluesky])
    X::UserClient.http_stub       = ->(*) { { status: "201", body: { "data" => { "id" => "X-OK" } } } }
    Bluesky::UserClient.http_stub = ->(*) { { status: "400", body: { "error" => "InvalidRequest" } } }

    sign_in_as(@owner)
    post publish_workspace_draft_path(workspace_slug: @ws.slug, id: draft.id)
    draft.reload
    assert_equal "partial", draft.status
    assert draft.error.present?
  ensure
    Bluesky::UserClient.http_stub = nil
  end

  test "republishing a finished draft is rejected" do
    draft = @ws.workspace_drafts.create!(author: @owner, body: "done", target_platforms: %w[x],
                                         status: "published", published_at: 1.minute.ago)
    sign_in_as(@owner)
    assert_no_difference -> { WorkspacePost.count } do
      post publish_workspace_draft_path(workspace_slug: @ws.slug, id: draft.id)
    end
    assert_match /already processed/, flash[:alert]
  end

  test "edit renders the draft form for a pending draft" do
    draft = @ws.workspace_drafts.create!(author: @owner, body: "old body", target_platforms: %w[x])
    sign_in_as(@owner)
    get edit_workspace_draft_path(workspace_slug: @ws.slug, id: draft.id)
    assert_response :success
    assert_match "old body", response.body
    assert_match /name="target_platforms\[\]"/, response.body
  end

  test "edit rejects a published draft" do
    draft = @ws.workspace_drafts.create!(author: @owner, body: "done", target_platforms: %w[x],
                                         status: "published", published_at: 1.minute.ago)
    sign_in_as(@owner)
    get edit_workspace_draft_path(workspace_slug: @ws.slug, id: draft.id)
    assert_redirected_to social_workspace_path(@ws.slug)
    assert_match /already been processed/, flash[:alert]
  end

  test "update changes body + target_platforms" do
    draft = @ws.workspace_drafts.create!(author: @owner, body: "before", target_platforms: %w[x])
    sign_in_as(@owner)
    patch workspace_draft_path(workspace_slug: @ws.slug, id: draft.id),
          params: { body: "after", target_platforms: [ "x", "bluesky" ] }
    assert_redirected_to social_workspace_path(@ws.slug)
    assert_equal "after", draft.reload.body
    assert_equal %w[x bluesky], draft.target_platforms
  end

  test "update rejects empty body" do
    draft = @ws.workspace_drafts.create!(author: @owner, body: "keep", target_platforms: %w[x])
    sign_in_as(@owner)
    patch workspace_draft_path(workspace_slug: @ws.slug, id: draft.id),
          params: { body: "", target_platforms: [ "x" ] }
    assert_equal "keep", draft.reload.body
    assert_redirected_to edit_workspace_draft_path(workspace_slug: @ws.slug, id: draft.id)
    assert_match /can't be empty/, flash[:alert]
  end

  test "rewrite calls AI with existing body + topic, stashes suggestion in flash" do
    draft = @ws.workspace_drafts.create!(author: @owner, body: "long original body, way too verbose", target_platforms: %w[x])

    captured = nil
    WorkspaceAi::Drafter.stub = ->(prompt) {
      captured = prompt
      OpenStruct.new(
        content: [ OpenStruct.new(text: "tight rewrite") ],
        usage:   OpenStruct.new(input_tokens: 50, output_tokens: 10)
      )
    }
    ENV["ANTHROPIC_API_KEY"] = "stub"

    sign_in_as(@owner)
    post rewrite_workspace_draft_path(workspace_slug: @ws.slug, id: draft.id),
         params: { topic: "Make it punchier" }
    assert_redirected_to edit_workspace_draft_path(workspace_slug: @ws.slug, id: draft.id)
    assert_match "long original body", captured
    assert_match "Make it punchier",   captured
    assert_equal "tight rewrite", flash[:draft_text]

    # Body in the DB is NOT touched until the user saves
    assert_equal "long original body, way too verbose", draft.reload.body
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
    WorkspaceAi::Drafter.stub = nil
  end

  test "destroy removes a draft" do
    draft = @ws.workspace_drafts.create!(author: @owner, body: "delete me", target_platforms: %w[x])
    sign_in_as(@owner)
    assert_difference -> { WorkspaceDraft.count }, -1 do
      delete workspace_draft_path(workspace_slug: @ws.slug, id: draft.id)
    end
  end
end

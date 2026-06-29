require "test_helper"
require "ostruct"

# Brian's "snap a photo, let the agent caption it, post it to X" flow:
# upload -> AI vision draft -> review -> publish with native X media.
class WorkspaceImagePostsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "wi-o-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @ws    = Workspace.create!(name: "Image WS", owner: @owner)
    @acct  = @ws.social_accounts.create!(
      platform: "x", connected_by: @owner, handle: "@magenta", external_id: SecureRandom.hex(4),
      access_token: "AT", refresh_token: "RT", token_expires_at: 2.hours.from_now,
      scopes: "tweet.write media.write users.read offline.access", status: "active"
    )
    ENV["ANTHROPIC_API_KEY"] = "stub"
  end

  teardown do
    WorkspaceAi::Drafter.stub = nil
    X::UserClient.http_stub   = nil
    X::UserClient.media_stub  = nil
  end

  def png_upload(type = "image/png")
    fixture_file_upload("sample_bottle.png", type)
  end

  test "draft from image captions via AI vision and attaches the photo" do
    captured = nil
    WorkspaceAi::Drafter.stub = ->(prompt) {
      captured = prompt
      OpenStruct.new(content: [ OpenStruct.new(text: "fresh microgreens today #local") ],
                     usage:   OpenStruct.new(input_tokens: 100, output_tokens: 30))
    }

    sign_in_as(@owner)
    assert_difference -> { WorkspaceDraft.count }, 1 do
      post workspace_draft_from_image_path(workspace_slug: @ws.slug),
           params: { image: png_upload, topic: "July 4th" }
    end

    draft = WorkspaceDraft.last
    assert_equal "fresh microgreens today #local", draft.body
    assert draft.image.attached?, "image should be attached to the draft"
    assert_equal %w[x], draft.target_platforms
    assert_redirected_to edit_workspace_draft_path(workspace_slug: @ws.slug, id: draft.id)
    assert_match(/attached image/i, captured)
    assert_match(/July 4th/, captured)

    # The edit page is Brian's review screen: it must render with the photo
    # preview and the "Post now" button.
    follow_redirect!
    assert_response :success
    assert_select "img"
    assert_select "button[name=commit][value=post]", text: "Post now"
  end

  test "from_image still saves the photo when the AI caption fails" do
    WorkspaceAi::Drafter.stub = ->(_prompt) { raise "vision down" }
    sign_in_as(@owner)
    assert_difference -> { WorkspaceDraft.count }, 1 do
      post workspace_draft_from_image_path(workspace_slug: @ws.slug), params: { image: png_upload }
    end
    draft = WorkspaceDraft.last
    assert draft.image.attached?
    assert draft.body.present?, "draft needs a placeholder body to satisfy validation"
  end

  test "from_image rejects a non-image upload" do
    sign_in_as(@owner)
    assert_no_difference -> { WorkspaceDraft.count } do
      post workspace_draft_from_image_path(workspace_slug: @ws.slug), params: { image: png_upload("text/plain") }
    end
    assert_match(/must be a JPEG/i, flash[:alert])
  end

  test "publishing a draft with an attached image uploads media then posts to X" do
    draft = @ws.workspace_drafts.create!(author: @owner, body: "look at this", target_platforms: %w[x], status: "draft")
    draft.image.attach(io: File.open(Rails.root.join("test/fixtures/files/sample_bottle.png")), filename: "b.png", content_type: "image/png")

    media_calls = []
    X::UserClient.media_stub = ->(params, _file, _bearer) {
      media_calls << params[:command]
      case params[:command]
      when "INIT"     then { status: "202", body: { "data" => { "id" => "MEDIA-9" } } }
      when "APPEND"   then { status: "204", body: {} }
      when "FINALIZE" then { status: "200", body: { "data" => { "id" => "MEDIA-9" } } }
      end
    }
    tweet_payload = nil
    X::UserClient.http_stub = ->(_method, _url, payload, _bearer) {
      tweet_payload = payload
      { status: "201", body: { "data" => { "id" => "TID-IMG" } } }
    }

    sign_in_as(@owner)
    post publish_workspace_draft_path(workspace_slug: @ws.slug, id: draft.id)

    assert_equal %w[INIT APPEND FINALIZE], media_calls
    assert_equal({ media_ids: [ "MEDIA-9" ] }, tweet_payload[:media])

    wp = WorkspacePost.last
    assert_equal "posted",  wp.status
    assert_equal "TID-IMG", wp.remote_id
    assert wp.image.attached?, "posted row should carry the image for the history thumbnail"
  end

  test "a failed media upload fails the post without tweeting" do
    draft = @ws.workspace_drafts.create!(author: @owner, body: "x", target_platforms: %w[x], status: "draft")
    draft.image.attach(io: File.open(Rails.root.join("test/fixtures/files/sample_bottle.png")), filename: "b.png", content_type: "image/png")

    X::UserClient.media_stub = ->(*) { { status: "403", body: { "detail" => "media.write missing" } } }
    tweeted = false
    X::UserClient.http_stub = ->(*) { tweeted = true; { status: "201", body: { "data" => { "id" => "NO" } } } }

    sign_in_as(@owner)
    post publish_workspace_draft_path(workspace_slug: @ws.slug, id: draft.id)

    refute tweeted, "should not tweet if the image upload failed"
    assert_equal "failed", WorkspacePost.last.status
    assert_match(/image upload/, WorkspacePost.last.error)
  end
end

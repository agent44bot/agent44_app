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
    SocialImage.fetch_stub    = nil
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

    media_uploads = 0
    X::UserClient.media_stub = ->(fields, _bearer) {
      media_uploads += 1
      assert_equal "tweet_image", fields["media_category"]
      assert fields["media"][:data].present?, "the image bytes must be sent as the media part"
      { status: "200", body: { "data" => { "id" => "MEDIA-9" } } }
    }
    tweet_payload = nil
    X::UserClient.http_stub = ->(_method, _url, payload, _bearer) {
      tweet_payload = payload
      { status: "201", body: { "data" => { "id" => "TID-IMG" } } }
    }

    sign_in_as(@owner)
    post publish_workspace_draft_path(workspace_slug: @ws.slug, id: draft.id)

    assert_equal 1, media_uploads, "one single-shot media upload"
    assert_equal({ media_ids: [ "MEDIA-9" ] }, tweet_payload[:media])

    wp = WorkspacePost.last
    assert_equal "posted",  wp.status
    assert_equal "TID-IMG", wp.remote_id
    assert wp.image.attached?, "posted row should carry the image for the history thumbnail"
  end

  test "a url image is fetched and uploaded to X as native media, not a link card" do
    SocialImage.fetch_stub = ->(url) {
      assert_equal "https://nykitchen.com/event.jpg", url
      [ "FETCHED_JPEG_BYTES", "image/jpeg" ]
    }
    media_uploads = 0
    X::UserClient.media_stub = ->(fields, _bearer) {
      media_uploads += 1
      assert_equal "tweet_image", fields["media_category"]
      assert_equal "FETCHED_JPEG_BYTES", fields["media"][:data]
      { status: "200", body: { "data" => { "id" => "MEDIA-URL" } } }
    }
    tweet_payload = nil
    X::UserClient.http_stub = ->(_method, _url, payload, _bearer) {
      tweet_payload = payload
      { status: "201", body: { "data" => { "id" => "TID-URL" } } }
    }

    sign_in_as(@owner)
    draft = @ws.workspace_drafts.create!(author: @owner, body: "event", target_platforms: %w[x],
      image_url: "https://nykitchen.com/event.jpg")
    result = WorkspaceDrafts::Publisher.new(draft).call

    assert result.all_ok?, "publish failed: #{result.failures.inspect}"
    assert_equal 1, media_uploads, "the url image should be uploaded as native media"
    assert_equal({ media_ids: [ "MEDIA-URL" ] }, tweet_payload[:media])
    assert_equal "TID-URL", WorkspacePost.last.remote_id
  end

  test "a url image that cannot upload still posts the tweet as text" do
    SocialImage.fetch_stub   = ->(_url) { [ "BYTES", "image/jpeg" ] }
    X::UserClient.media_stub = ->(*) { { status: "413", body: { "detail" => "too large" } } }
    tweet_payload = nil
    X::UserClient.http_stub = ->(_method, _url, payload, _bearer) {
      tweet_payload = payload
      { status: "201", body: { "data" => { "id" => "TID-TEXT" } } }
    }

    sign_in_as(@owner)
    draft = @ws.workspace_drafts.create!(author: @owner, body: "event", target_platforms: %w[x],
      image_url: "https://nykitchen.com/huge.jpg")
    result = WorkspaceDrafts::Publisher.new(draft).call

    assert result.all_ok?, "the tweet should still go out as text"
    assert_nil tweet_payload[:media], "no media attached when upload failed"
    assert_equal "posted", WorkspacePost.last.status
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

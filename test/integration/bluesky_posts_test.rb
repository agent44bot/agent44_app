require "test_helper"

class BlueskyPostsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "bp-o-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @ws    = Workspace.create!(name: "Bsky Posts WS", owner: @owner)
    @bsky  = @ws.social_accounts.create!(
      platform: "bluesky", connected_by: @owner,
      handle: "@agent44.bsky.social", display_name: "agent44.bsky.social",
      external_id: "did:plc:abc",
      access_token: "AT", refresh_token: "RT", token_secret: "app-pw",
      token_expires_at: 2.hours.from_now, status: "active"
    )
  end

  teardown do
    Bluesky::UserClient.http_stub = nil
    Bluesky::Session.http_stub = nil
  end

  test "post to Bluesky creates a record and stores the rkey" do
    Bluesky::UserClient.http_stub = ->(method, url, payload, bearer) {
      assert_equal :post, method
      assert url.end_with?("createRecord")
      assert_equal "did:plc:abc", payload[:repo]
      assert_equal "app.bsky.feed.post", payload[:collection]
      assert_equal "hello bsky", payload[:record][:text]
      assert_equal "AT", bearer
      { status: "200", body: { "uri" => "at://did:plc:abc/app.bsky.feed.post/3kabcd", "cid" => "bafy..." } }
    }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, 1 do
      post workspace_posts_path(workspace_slug: @ws.slug),
           params: { body: "hello bsky", target_platforms: [ "bluesky" ] }
    end
    wp = WorkspacePost.last
    assert_equal "posted",  wp.status
    assert_equal "bluesky", wp.platform
    assert_equal "3kabcd",  wp.remote_id
    assert_equal "https://bsky.app/profile/agent44.bsky.social/post/3kabcd", wp.remote_url
  end

  test "401 triggers a refreshSession + retry" do
    call_count = 0
    Bluesky::UserClient.http_stub = ->(method, url, payload, bearer) {
      call_count += 1
      if call_count == 1
        { status: "401", body: { "error" => "ExpiredToken" } }
      else
        { status: "200", body: { "uri" => "at://did:plc:abc/app.bsky.feed.post/retry1" } }
      end
    }
    refreshed = false
    Bluesky::Session.http_stub = ->(method, url, _payload, headers) {
      refreshed = true if url.end_with?("refreshSession") && headers["Authorization"] == "Bearer RT"
      [ "200", { "did" => "did:plc:abc", "handle" => "agent44.bsky.social",
                "accessJwt" => "NEW-AT", "refreshJwt" => "NEW-RT" } ]
    }

    sign_in_as(@owner)
    post workspace_posts_path(workspace_slug: @ws.slug),
         params: { body: "after 401", target_platforms: [ "bluesky" ] }

    assert refreshed,            "Bluesky refreshSession should have fired"
    assert_equal 2, call_count,  "should retry once after refresh"
    assert_equal "retry1", WorkspacePost.last.remote_id
    assert_equal "NEW-AT", @bsky.reload.access_token
  end

  test "trashcan on a Bluesky post calls deleteRecord and drops the row" do
    wp = @ws.workspace_posts.create!(author: @owner, social_account: @bsky, platform: "bluesky",
      body: "delete me", status: "posted", remote_id: "rkey-9",
      remote_url: "https://bsky.app/profile/agent44.bsky.social/post/rkey-9", posted_at: Time.current)

    called = []
    Bluesky::UserClient.http_stub = ->(method, url, payload, _bearer) {
      called << url
      assert_equal "rkey-9", payload[:rkey]
      { status: "200", body: {} }
    }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, -1 do
      delete workspace_post_path(workspace_slug: @ws.slug, id: wp.id)
    end
    assert called.first.end_with?("deleteRecord")
  end

  test "multi-platform fanout creates one WorkspacePost per platform" do
    @ws.social_accounts.create!(
      platform: "x", connected_by: @owner, handle: "@agent44", external_id: "x-1",
      access_token: "X-AT", refresh_token: "X-RT", token_expires_at: 2.hours.from_now, status: "active"
    )
    X::UserClient.http_stub       = ->(*) { { status: "201", body: { "data" => { "id" => "TID" } } } }
    Bluesky::UserClient.http_stub = ->(*) { { status: "200", body: { "uri" => "at://did:plc:abc/app.bsky.feed.post/BID" } } }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, 2 do
      post workspace_posts_path(workspace_slug: @ws.slug),
           params: { body: "everywhere", target_platforms: [ "x", "bluesky" ] }
    end

    rows = @ws.workspace_posts.where(body: "everywhere").index_by(&:platform)
    assert_equal "TID", rows["x"].remote_id
    assert_equal "BID", rows["bluesky"].remote_id
    assert_equal "posted", rows["x"].status
    assert_equal "posted", rows["bluesky"].status
  ensure
    X::UserClient.http_stub = nil
  end

  test "partial failure leaves successes posted and surfaces the failed one" do
    @ws.social_accounts.create!(
      platform: "x", connected_by: @owner, handle: "@agent44", external_id: "x-2",
      access_token: "X-AT", refresh_token: "X-RT", token_expires_at: 2.hours.from_now, status: "active"
    )
    X::UserClient.http_stub       = ->(*) { { status: "201", body: { "data" => { "id" => "TID-OK" } } } }
    Bluesky::UserClient.http_stub = ->(*) { { status: "400", body: { "error" => "InvalidRequest", "message" => "Bad post" } } }

    sign_in_as(@owner)
    post workspace_posts_path(workspace_slug: @ws.slug),
         params: { body: "mixed", target_platforms: [ "x", "bluesky" ] }
    follow_redirect!
    assert_match /Partial/, response.body
    rows = @ws.workspace_posts.where(body: "mixed").index_by(&:platform)
    assert_equal "posted", rows["x"].status
    assert_equal "failed", rows["bluesky"].status
  ensure
    X::UserClient.http_stub = nil
  end

  test "post with image_url: uploads blob then embeds it in createRecord" do
    upload_calls = []
    Bluesky::UserClient.image_fetch_stub = ->(url) {
      assert_equal "https://nykitchen.com/photo.jpg", url
      [ "FAKE_JPEG_BYTES", "image/jpeg" ]
    }
    Bluesky::UserClient.http_stub = ->(method, url, payload, bearer) {
      upload_calls << url
      if url.end_with?("uploadBlob")
        assert_equal "FAKE_JPEG_BYTES", payload
        { status: "200", body: { "blob" => { "$type" => "blob", "ref" => { "$link" => "bafkrei123" }, "mimeType" => "image/jpeg", "size" => 16 } } }
      elsif url.end_with?("createRecord")
        embed = payload[:record][:embed]
        assert_equal "app.bsky.embed.images", embed["$type"]
        assert_equal "bafkrei123", embed[:images].first[:image].dig("ref", "$link")
        { status: "200", body: { "uri" => "at://did:plc:abc/app.bsky.feed.post/abc" } }
      else
        raise "unexpected #{url}"
      end
    }

    sign_in_as(@owner)
    # Drive the publisher path directly (closest to how a sent-from-NYK draft fans out)
    draft = @ws.workspace_drafts.create!(author: @owner, body: "with image",
      target_platforms: %w[bluesky], image_url: "https://nykitchen.com/photo.jpg")
    result = WorkspaceDrafts::Publisher.new(draft).call
    assert result.all_ok?, "publish failed: #{result.failures.inspect}"
    assert_equal 2, upload_calls.size, "expected uploadBlob + createRecord, got #{upload_calls.inspect}"
    assert upload_calls.any? { |u| u.end_with?("uploadBlob") }
  ensure
    Bluesky::UserClient.image_fetch_stub = nil
  end

  test "an oversized image_url is downscaled to fit Bluesky's 1MB limit" do
    # Regression: a >1MB event photo used to fail Bluesky ("image > 1MB") while
    # X posted fine. The URL path now downscales like the uploaded-image path.
    big = Vips::Image.gaussnoise(4000, 4000, sigma: 60).cast("uchar").jpegsave_buffer(Q: 100)
    assert big.bytesize > Bluesky::UserClient::MAX_IMAGE_BYTES, "fixture should exceed 1MB"

    uploaded_size = nil
    Bluesky::UserClient.image_fetch_stub = ->(_url) { [ big, "image/jpeg" ] }
    Bluesky::UserClient.http_stub = ->(_method, url, payload, _bearer) {
      if url.end_with?("uploadBlob")
        uploaded_size = payload.bytesize
        { status: "200", body: { "blob" => { "$type" => "blob", "ref" => { "$link" => "bafk1" }, "mimeType" => "image/jpeg", "size" => payload.bytesize } } }
      else
        { status: "200", body: { "uri" => "at://did:plc:abc/app.bsky.feed.post/z" } }
      end
    }

    sign_in_as(@owner)
    draft = @ws.workspace_drafts.create!(author: @owner, body: "big img",
      target_platforms: %w[bluesky], image_url: "https://nykitchen.com/big.jpg")
    result = WorkspaceDrafts::Publisher.new(draft).call

    assert result.all_ok?, "publish failed: #{result.failures.inspect}"
    assert uploaded_size, "uploadBlob was never called"
    assert uploaded_size <= Bluesky::UserClient::MAX_IMAGE_BYTES,
      "uploaded #{uploaded_size} bytes, still over the 1MB limit"
  ensure
    Bluesky::UserClient.image_fetch_stub = nil
  end

  test "image fetch failure still posts text without an image embed" do
    Bluesky::UserClient.image_fetch_stub = ->(_url) { nil }
    captured_payload = nil
    Bluesky::UserClient.http_stub = ->(_method, url, payload, _bearer) {
      assert url.end_with?("createRecord"), "should skip uploadBlob when the image cannot be fetched"
      captured_payload = payload
      { status: "200", body: { "uri" => "at://did:plc:abc/app.bsky.feed.post/noimage" } }
    }

    sign_in_as(@owner)
    draft = @ws.workspace_drafts.create!(author: @owner, body: "x",
      target_platforms: %w[bluesky], image_url: "https://bad.example/missing.jpg")
    result = WorkspaceDrafts::Publisher.new(draft).call
    assert result.all_ok?, "publish failed: #{result.failures.inspect}"
    assert_nil captured_payload[:record][:embed]
  ensure
    Bluesky::UserClient.image_fetch_stub = nil
  end

  test "non-image image_url response still posts text without uploading html" do
    Bluesky::UserClient.image_fetch_stub = ->(_url) { [ "<html>not an image</html>", "text/html" ] }
    captured_urls = []
    captured_payload = nil
    Bluesky::UserClient.http_stub = ->(_method, url, payload, _bearer) {
      captured_urls << url
      captured_payload = payload
      { status: "200", body: { "uri" => "at://did:plc:abc/app.bsky.feed.post/html" } }
    }

    sign_in_as(@owner)
    draft = @ws.workspace_drafts.create!(author: @owner, body: "html image",
      target_platforms: %w[bluesky], image_url: "https://nykitchen.com/photo.jpg")
    result = WorkspaceDrafts::Publisher.new(draft).call
    assert result.all_ok?, "publish failed: #{result.failures.inspect}"
    assert_equal 1, captured_urls.size
    assert captured_urls.first.end_with?("createRecord")
    assert_nil captured_payload[:record][:embed]
  ensure
    Bluesky::UserClient.image_fetch_stub = nil
  end

  test "post text gets facets attached so URLs and hashtags render clickable" do
    captured_payload = nil
    Bluesky::UserClient.http_stub = ->(_method, _url, payload, _bearer) {
      captured_payload = payload
      { status: "200", body: { "uri" => "at://did:plc:abc/app.bsky.feed.post/with-facets" } }
    }
    sign_in_as(@owner)
    post workspace_posts_path(workspace_slug: @ws.slug),
         params: { body: "Class at https://nykitchen.com/x #NYKitchen", target_platforms: [ "bluesky" ] }

    facets = captured_payload[:record][:facets]
    assert_equal 2, facets.size, "expected one link facet + one tag facet"
    assert facets.any? { |f| f[:features].first["$type"] == "app.bsky.richtext.facet#link" }
    assert facets.any? { |f| f[:features].first["$type"] == "app.bsky.richtext.facet#tag" }
  end

  test "no platforms checked is rejected without creating rows" do
    sign_in_as(@owner)
    assert_no_difference -> { WorkspacePost.count } do
      post workspace_posts_path(workspace_slug: @ws.slug),
           params: { body: "no targets" }
    end
    follow_redirect!
    assert_match /at least one platform/i, response.body
  end

  test "a draft's attached image is uploaded as a blob and embedded on Bluesky" do
    draft = @ws.workspace_drafts.create!(author: @owner, body: "look", target_platforms: %w[bluesky], status: "draft")
    # content_type jpeg + small => passes through without re-encoding (no vips).
    draft.image.attach(io: File.open(Rails.root.join("test/fixtures/files/sample_bottle.png")), filename: "b.jpg", content_type: "image/jpeg")

    uploaded = false
    embed = nil
    Bluesky::UserClient.http_stub = ->(_method, url, payload, _bearer) {
      if url.end_with?("uploadBlob")
        uploaded = true
        { status: "200", body: { "blob" => { "$type" => "blob", "ref" => { "$link" => "bafyimg" }, "mimeType" => "image/jpeg", "size" => payload.bytesize } } }
      else
        embed = payload[:record][:embed]
        { status: "200", body: { "uri" => "at://did:plc:abc/app.bsky.feed.post/img1" } }
      end
    }

    sign_in_as(@owner)
    post publish_workspace_draft_path(workspace_slug: @ws.slug, id: draft.id)

    assert uploaded, "the attached image should be uploaded to Bluesky as a blob"
    refute_nil embed, "the post record should carry an images embed"
    assert_equal "app.bsky.embed.images", embed["$type"]
    assert_equal "posted", WorkspacePost.where(platform: "bluesky").last.status
  end

  test "bluesky_image_bytes re-encodes an oversized non-jpeg attachment to a small jpeg" do
    png   = Vips::Image.gaussnoise(4000, 4000, sigma: 60).cast("uchar").pngsave_buffer
    assert png.bytesize > Bluesky::UserClient::MAX_IMAGE_BYTES, "PNG fixture should exceed 1MB"
    draft = @ws.workspace_drafts.create!(author: @owner, body: "x", target_platforms: %w[bluesky], status: "draft")
    draft.image.attach(io: StringIO.new(png), filename: "x.png", content_type: "image/png")

    dispatcher = WorkspacePosts::Dispatcher.new(@ws, author: @owner, body: "x", platforms: %w[bluesky], image: draft.image)
    bytes, mime = dispatcher.send(:bluesky_image_bytes)

    assert_equal "image/jpeg", mime, "oversized non-jpeg is re-encoded to jpeg"
    assert bytes.bytesize <= Bluesky::UserClient::MAX_IMAGE_BYTES, "must fit Bluesky's 1MB blob limit"
  end

  test "bluesky_image_bytes passes an under-limit attachment through unchanged" do
    png   = Vips::Image.black(200, 200).pngsave_buffer
    draft = @ws.workspace_drafts.create!(author: @owner, body: "x", target_platforms: %w[bluesky], status: "draft")
    draft.image.attach(io: StringIO.new(png), filename: "x.png", content_type: "image/png")

    dispatcher = WorkspacePosts::Dispatcher.new(@ws, author: @owner, body: "x", platforms: %w[bluesky], image: draft.image)
    bytes, mime = dispatcher.send(:bluesky_image_bytes)

    assert_equal "image/png", mime, "small PNG is left as-is (Bluesky accepts PNG)"
    assert_equal png.bytesize, bytes.bytesize
  end
end

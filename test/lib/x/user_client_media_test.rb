require "test_helper"

class XUserClientMediaTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email_address: "xum-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "X WS", owner: @owner)
    @acct  = @ws.social_accounts.create!(
      platform: "x", connected_by: @owner, handle: "@m", external_id: SecureRandom.hex(4),
      access_token: "AT", refresh_token: "RT", token_expires_at: 2.hours.from_now,
      scopes: "tweet.write media.write users.read offline.access", status: "active"
    )
  end

  teardown do
    X::UserClient.media_stub = nil
    X::UserClient.http_stub  = nil
  end

  test "media.write is in the default OAuth scopes (else uploads 403)" do
    assert_includes X::Oauth::DEFAULT_SCOPES, "media.write"
  end

  test "upload_media posts a single multipart request with media + media_category" do
    captured = nil
    X::UserClient.media_stub = ->(fields, bearer) {
      captured = fields
      assert_equal "AT", bearer
      { status: "200", body: { "data" => { "id" => "M-1" } } }
    }

    res = X::UserClient.new(@acct).upload_media("PNGBYTES", "image/png")
    assert res.ok?
    assert_equal "M-1", res.media_id
    assert_equal "tweet_image", captured["media_category"]
    assert_equal "image/png",   captured["media"][:content_type]
    assert_equal "PNGBYTES",    captured["media"][:data]
  end

  test "upload_media surfaces a failure (e.g. missing media.write)" do
    X::UserClient.media_stub = ->(*) { { status: "403", body: { "detail" => "media.write missing" } } }
    res = X::UserClient.new(@acct).upload_media("X", "image/png")
    refute res.ok?
    assert_match(/image upload/, res.error)
    assert_match(/media.write/, res.error)
  end

  test "upload_media rejects an oversized image before any HTTP call" do
    called = false
    X::UserClient.media_stub = ->(*) { called = true; {} }
    big = "a" * (X::UserClient::MAX_IMAGE_BYTES + 1)
    res = X::UserClient.new(@acct).upload_media(big, "image/png")
    refute res.ok?
    refute called, "should not hit X for an oversized image"
    assert_match(/5MB/, res.error)
  end

  test "post_tweet attaches media_ids in the payload" do
    captured = nil
    X::UserClient.http_stub = ->(_method, _url, payload, _bearer) { captured = payload; { status: "201", body: { "data" => { "id" => "T" } } } }
    res = X::UserClient.new(@acct).post_tweet("hi", media_ids: [ "M-1" ])
    assert res.ok?
    assert_equal({ media_ids: [ "M-1" ] }, captured[:media])
  end

  test "post_tweet without media keeps a plain text payload" do
    captured = nil
    X::UserClient.http_stub = ->(_method, _url, payload, _bearer) { captured = payload; { status: "201", body: { "data" => { "id" => "T" } } } }
    X::UserClient.new(@acct).post_tweet("hi")
    assert_nil captured[:media]
    assert_equal "hi", captured[:text]
  end
end

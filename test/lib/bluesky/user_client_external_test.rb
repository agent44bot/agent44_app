require "test_helper"

# Bluesky link-card (app.bsky.embed.external) support: an external embed makes
# the whole card, image included, tap through to the URL. The HTTP + image
# fetch are stubbed so nothing leaves the process.
class BlueskyUserClientExternalTest < ActiveSupport::TestCase
  setup do
    owner = User.create!(email_address: "bx-#{SecureRandom.hex(4)}@example.com")
    ws = Workspace.create!(name: "Bsky Ext WS", owner: owner)
    @account = ws.social_accounts.create!(
      platform: "bluesky", connected_by: owner, handle: "@nyk.bsky.social",
      external_id: "did:plc:ext", access_token: "AT", refresh_token: "RT",
      token_expires_at: 2.hours.from_now, status: "active"
    )
  end

  teardown do
    Bluesky::UserClient.http_stub = nil
    Bluesky::UserClient.image_fetch_stub = nil
  end

  def external
    { uri: "https://nykitchen.com/event/curry/", title: "Perfect Curry Class",
      description: "Cook Indian food with us.", image_url: "https://nykitchen.com/curry.jpg" }
  end

  test "builds an external embed with a thumb blob from the card image" do
    # A tiny valid-ish JPEG byte string; ImageFit passes small bytes through.
    Bluesky::UserClient.image_fetch_stub = ->(_url) { [ "\xFF\xD8\xFFsmalljpeg".b, "image/jpeg" ] }

    captured = nil
    Bluesky::UserClient.http_stub = lambda do |method, url, payload, _bearer|
      if url.end_with?("uploadBlob")
        { status: "200", body: { "blob" => { "$type" => "blob", "ref" => { "$link" => "bafblob" }, "mimeType" => "image/jpeg", "size" => 10 } } }
      else
        captured = payload
        { status: "200", body: { "uri" => "at://did:plc:ext/app.bsky.feed.post/xyz" } }
      end
    end

    res = Bluesky::UserClient.new(@account).post_text("Book now!", external: external)
    assert res.ok?, res.error

    embed = captured[:record][:embed]
    assert_equal "app.bsky.embed.external", embed["$type"]
    assert_equal "https://nykitchen.com/event/curry/", embed[:external][:uri]
    assert_equal "Perfect Curry Class", embed[:external][:title]
    assert_equal "Cook Indian food with us.", embed[:external][:description]
    assert embed[:external][:thumb], "expected a thumb blob ref"
  end

  test "still posts the card when the thumb image cannot be fetched" do
    Bluesky::UserClient.image_fetch_stub = ->(_url) { nil } # fetch fails

    captured = nil
    Bluesky::UserClient.http_stub = lambda do |_method, _url, payload, _bearer|
      captured = payload
      { status: "200", body: { "uri" => "at://did:plc:ext/app.bsky.feed.post/nothumb" } }
    end

    res = Bluesky::UserClient.new(@account).post_text("Book now!", external: external)
    assert res.ok?, res.error
    embed = captured[:record][:embed]
    assert_equal "app.bsky.embed.external", embed["$type"]
    assert_not embed[:external].key?(:thumb), "no thumb when the image fetch fails"
    assert_equal "Perfect Curry Class", embed[:external][:title]
  end
end

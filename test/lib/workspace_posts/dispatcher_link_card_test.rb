require "test_helper"

# In link-card mode the Dispatcher must NOT attach native media on X (so X
# renders the page's own preview card) and must send an app.bsky.embed.external
# on Bluesky. All network + card fetch is stubbed.
class DispatcherLinkCardTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email_address: "dlc-#{SecureRandom.hex(4)}@example.com")
    @ws = Workspace.create!(name: "LinkCard WS", owner: @owner)
    @ws.social_accounts.create!(platform: "x", connected_by: @owner, handle: "@nyk",
                                external_id: "x-1", access_token: "AT", refresh_token: "RT",
                                token_expires_at: 2.hours.from_now, status: "active")
    @ws.social_accounts.create!(platform: "bluesky", connected_by: @owner, handle: "@nyk.bsky.social",
                                external_id: "did:plc:x", access_token: "AT", refresh_token: "RT",
                                token_expires_at: 2.hours.from_now, status: "active")
    SocialCard.stub = ->(url) { SocialCard::Card.new(url: url, title: "Curry Class", description: "Cook with us", image_url: nil) }
  end

  teardown do
    SocialCard.stub = nil
    X::UserClient.http_stub = nil
    Bluesky::UserClient.http_stub = nil
  end

  def dispatch!
    WorkspacePosts::Dispatcher.new(
      @ws, author: @owner, body: "Book now!\n\nhttps://nykitchen.com/event/curry/",
      platforms: %w[x bluesky], image_url: "https://nykitchen.com/curry.jpg",
      source_url: "https://nykitchen.com/event/curry/", link_card: true
    ).dispatch
  end

  test "X posts text only (no native media) so its own card renders" do
    x_payload = nil
    X::UserClient.http_stub = ->(_m, _u, payload, _b) { x_payload = payload; { status: "201", body: { "data" => { "id" => "T1" } } } }
    Bluesky::UserClient.http_stub = ->(_m, _u, _p, _b) { { status: "200", body: { "uri" => "at://did:plc:x/app.bsky.feed.post/b1" } } }

    result = dispatch!
    assert result.all_ok?, result.failures.join(", ")
    assert_nil x_payload[:media], "link-card mode must not attach native media on X"
    assert_includes x_payload[:text], "nykitchen.com/event/curry/"
  end

  test "Bluesky sends an external embed pointing at the signup URL" do
    X::UserClient.http_stub = ->(_m, _u, _p, _b) { { status: "201", body: { "data" => { "id" => "T1" } } } }
    bsky_payload = nil
    Bluesky::UserClient.http_stub = ->(_m, _u, payload, _b) { bsky_payload = payload; { status: "200", body: { "uri" => "at://did:plc:x/app.bsky.feed.post/b1" } } }

    result = dispatch!
    assert result.all_ok?, result.failures.join(", ")
    embed = bsky_payload[:record][:embed]
    assert_equal "app.bsky.embed.external", embed["$type"]
    assert_equal "https://nykitchen.com/event/curry/", embed[:external][:uri]
    assert_equal "Curry Class", embed[:external][:title]
  end
end

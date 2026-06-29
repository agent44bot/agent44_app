require "test_helper"

# Recent posts is tabbed by platform: X / Bluesky / Threads / Facebook /
# Instagram, each with a connected (green check) or not-connected (red dot)
# indicator. Connected tabs list posts + a Disconnect control; unconnected
# tabs offer a Connect CTA. The tabs are the single home for connections (the
# old Settings panel was retired).
class SocialPlatformTabsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "spt-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @ws    = Workspace.create!(name: "Tabs WS", owner: @owner)
    @ws.social_accounts.create!(platform: "x", connected_by: @owner, handle: "@goe", external_id: "x1",
      access_token: "AT", refresh_token: "RT", token_expires_at: 2.hours.from_now, status: "active")
    @ws.social_accounts.create!(platform: "bluesky", connected_by: @owner, handle: "@goe.bsky.social", external_id: "did:1",
      access_token: "AT", refresh_token: "RT", token_secret: "pw", token_expires_at: 2.hours.from_now, status: "active")

    @ws.workspace_posts.create!(author: @owner, platform: "x", body: "X MICROGREENS POST", status: "posted",
      remote_id: "1", remote_url: "https://x.com/goe/status/1", posted_at: Time.current)
    @ws.workspace_posts.create!(author: @owner, platform: "bluesky", body: "BLUESKY MICROGREENS POST", status: "posted",
      remote_id: "2", remote_url: "https://bsky.app/profile/goe/post/2", posted_at: Time.current)
  end

  test "renders a tab per platform with connection status indicators" do
    sign_in_as(@owner)
    get social_workspace_path(@ws.slug)
    assert_response :success

    assert_select "[data-controller=tabs]"
    %w[x bluesky threads facebook instagram].each do |key|
      assert_select "[data-tab-name=?]", key
    end
    assert_select "[data-tab-name=x] [aria-label=?]", "connected"
    assert_select "[data-tab-name=bluesky] [aria-label=?]", "connected"
    assert_select "[data-tab-name=threads] [aria-label=?]", "not connected"
    assert_select "[data-tab-name=facebook] [aria-label=?]", "not connected"
    assert_select "[data-tab-name=instagram] [aria-label=?]", "not connected"
  end

  test "connected tabs show posts + Disconnect; unconnected tabs offer Connect" do
    sign_in_as(@owner)
    get social_workspace_path(@ws.slug)

    assert_match "X MICROGREENS POST", response.body
    assert_match "BLUESKY MICROGREENS POST", response.body
    assert_select "button", text: /Disconnect/
    assert_match "Facebook isn't connected yet", response.body
    assert_match "Instagram isn't connected yet", response.body
    assert_match "Threads isn't connected yet", response.body
  end

  test "the old Settings panel and gear are gone" do
    sign_in_as(@owner)
    get social_workspace_path(@ws.slug)
    assert_select "h2", text: /Connected accounts/, count: 0
    assert_select "button[aria-label=?]", "Social Agent settings", count: 0
  end
end

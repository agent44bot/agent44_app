require "test_helper"
require "ostruct"

# SocialListenJob searches Bluesky + Reddit, scores fresh posts, and stores the
# good ones as SocialLeads. All network + AI is stubbed (nothing leaves the
# process).
class SocialListenJobTest < ActiveJob::TestCase
  setup do
    Setting.delete_all
    @rich = User.create!(email_address: "sl-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @nyk = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @rich }
    @nyk.social_accounts.create!(platform: "bluesky", external_id: "did:plc:x", handle: "@nyk.bsky.social",
                                 connected_by: @rich, access_token: "AT", refresh_token: "RT",
                                 token_expires_at: 2.hours.from_now, status: "active")

    Bluesky::UserClient.http_stub = lambda do |_method, _url, _payload, _bearer|
      { status: "200", body: { "posts" => [
        { "uri" => "at://did:plc:foodie/app.bsky.feed.post/1",
          "author" => { "handle" => "foodie.bsky.social" },
          "record" => { "text" => "Best cooking class near Canandaigua?" },
          "indexedAt" => "2026-07-02T12:00:00Z" } ] } }
    end
    Reddit::Search.http_stub = lambda do |_url|
      { "data" => { "children" => [ { "data" => {
        "name" => "t3_abc", "author" => "rocfoodie", "title" => "Date night cooking ideas?",
        "selftext" => "in Rochester", "permalink" => "/r/Rochester/abc", "created_utc" => 1_751_000_000 } } ] } }
    end
    stub_score(80)
  end

  teardown do
    Bluesky::UserClient.http_stub = nil
    Reddit::Search.http_stub = nil
    SocialAi::LeadScout.stub = nil
  end

  def stub_score(score, reply: "Come cook with us!")
    SocialAi::LeadScout.stub = lambda do |candidate:|
      OpenStruct.new(content: [ OpenStruct.new(text: { score: score, reason: "local", reply: reply }.to_json) ],
                     usage: OpenStruct.new(input_tokens: 10, output_tokens: 10))
    end
  end

  test "off by default: no slugs configured -> nothing happens" do
    SocialListenJob.perform_now
    assert_equal 0, SocialLead.count
  end

  test "stores scored bluesky + reddit leads for an enabled workspace, deduped across queries" do
    Setting.set("social_listen:slugs", "nykitchen")
    SocialListenJob.perform_now
    assert_equal 2, @nyk.social_leads.count, "one bluesky + one reddit (each query returns the same post)"
    bsky = @nyk.social_leads.find_by(platform: "bluesky")
    assert_equal 80, bsky.score
    assert_equal "Come cook with us!", bsky.draft_reply
    assert_equal "new", bsky.status
    assert @nyk.social_leads.exists?(platform: "reddit")
  end

  test "a second run does not duplicate existing leads" do
    Setting.set("social_listen:slugs", "nykitchen")
    SocialListenJob.perform_now
    SocialListenJob.perform_now
    assert_equal 2, @nyk.social_leads.count
  end

  test "skips candidates below the minimum score" do
    Setting.set("social_listen:slugs", "nykitchen")
    stub_score(10, reply: "")
    SocialListenJob.perform_now
    assert_equal 0, SocialLead.count
  end

  test "does not surface the workspace's own bluesky posts" do
    Setting.set("social_listen:slugs", "nykitchen")
    Bluesky::UserClient.http_stub = lambda do |_m, _u, _p, _b|
      { status: "200", body: { "posts" => [
        { "uri" => "at://self/app.bsky.feed.post/9", "author" => { "handle" => "nyk.bsky.social" },
          "record" => { "text" => "Join our class!" }, "indexedAt" => "2026-07-02T12:00:00Z" } ] } }
    end
    SocialListenJob.perform_now
    assert_equal 0, @nyk.social_leads.where(platform: "bluesky").count, "own posts are filtered out"
  end
end

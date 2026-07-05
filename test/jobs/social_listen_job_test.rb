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

    recent_iso = 2.days.ago.utc.iso8601
    recent_utc = 3.days.ago.to_i
    Bluesky::UserClient.http_stub = lambda do |_method, _url, _payload, _bearer|
      { status: "200", body: { "posts" => [
        { "uri" => "at://did:plc:foodie/app.bsky.feed.post/1",
          "author" => { "handle" => "foodie.bsky.social" },
          "record" => { "text" => "Best cooking class near Canandaigua?" },
          "indexedAt" => recent_iso } ] } }
    end
    Reddit::Search.http_stub = lambda do |_url|
      { "data" => { "children" => [ { "data" => {
        "name" => "t3_abc", "author" => "rocfoodie", "title" => "Date night cooking ideas?",
        "selftext" => "in Rochester", "permalink" => "/r/Rochester/abc", "created_utc" => recent_utc } } ] } }
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

  test "queries_for defaults to DEFAULT_QUERIES, overridable per workspace (comma/newline)" do
    assert_equal SocialListenJob::DEFAULT_QUERIES, SocialListenJob.queries_for(@nyk)
    Setting.set("social_listen:queries:#{@nyk.slug}", "wine tasting, beer tasting\ncooking class")
    assert_equal [ "wine tasting", "beer tasting", "cooking class" ], SocialListenJob.queries_for(@nyk)
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

  test "pushes one review notification (deep-linked to Echo) when leads land and a recipient is set" do
    Setting.set("social_listen:slugs", "nykitchen")
    Setting.set("social_listen:notify_user_ids", @rich.id.to_s)
    Notification.delete_all
    travel_to(Time.zone.parse("#{Date.current} 14:00")) { SocialListenJob.perform_now }
    n = Notification.where(source: "echo").last
    assert n, "expected an Echo review notification"
    assert_equal @rich, n.user
    assert_equal "/nykitchen/social", n.url
    assert_equal 1, Notification.where(source: "echo").count, "one push per run, not per lead"
  end

  test "no review push when no recipient is configured" do
    Setting.set("social_listen:slugs", "nykitchen")
    Notification.delete_all
    travel_to(Time.zone.parse("#{Date.current} 14:00")) { SocialListenJob.perform_now }
    assert_equal 0, Notification.where(source: "echo").count
    assert @nyk.social_leads.new_leads.any?, "leads are still stored, just no push"
  end

  test "pushes 24/7, including overnight (users mute on their device)" do
    Setting.set("social_listen:slugs", "nykitchen")
    Setting.set("social_listen:notify_user_ids", @rich.id.to_s)
    Notification.delete_all
    travel_to(Time.zone.parse("#{Date.current} 02:00")) { SocialListenJob.perform_now }
    assert_equal 1, Notification.where(source: "echo").count, "a 2am run still pushes"
  end

  test "skips stale posts older than the recency window" do
    Setting.set("social_listen:slugs", "nykitchen")
    old_iso = 40.days.ago.utc.iso8601
    Bluesky::UserClient.http_stub = lambda do |_m, _u, _p, _b|
      { status: "200", body: { "posts" => [
        { "uri" => "at://old/1", "author" => { "handle" => "someone.bsky.social" },
          "record" => { "text" => "old cooking class post" }, "indexedAt" => old_iso } ] } }
    end
    Reddit::Search.http_stub = ->(_url) { { "data" => { "children" => [] } } }
    SocialListenJob.perform_now
    assert_equal 0, SocialLead.count, "posts older than the window are not stored"
  end

  test "does not surface the workspace's own bluesky posts" do
    Setting.set("social_listen:slugs", "nykitchen")
    Bluesky::UserClient.http_stub = lambda do |_m, _u, _p, _b|
      { status: "200", body: { "posts" => [
        { "uri" => "at://self/app.bsky.feed.post/9", "author" => { "handle" => "nyk.bsky.social" },
          "record" => { "text" => "Join our class!" }, "indexedAt" => 1.day.ago.utc.iso8601 } ] } }
    end
    SocialListenJob.perform_now
    assert_equal 0, @nyk.social_leads.where(platform: "bluesky").count, "own posts are filtered out"
  end
end

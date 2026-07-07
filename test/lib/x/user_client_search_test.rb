require "test_helper"

class XUserClientSearchTest < ActiveSupport::TestCase
  setup do
    owner = User.create!(email_address: "x-#{SecureRandom.hex(4)}@example.com")
    ws = Workspace.create!(name: "X WS", slug: "x-#{SecureRandom.hex(4)}", owner: owner)
    @account = ws.social_accounts.create!(platform: "x", connected_by: owner, handle: "@nykitchen_roc",
                                          external_id: "111", access_token: "AT", refresh_token: "RT",
                                          token_expires_at: 2.hours.from_now, status: "active")
  end

  teardown { X::UserClient.http_stub = nil }

  test "search_recent resolves handles, builds urls, and drops empty-text tweets" do
    captured = nil
    X::UserClient.http_stub = lambda do |_method, url, _payload, _bearer|
      captured = url
      { status: "200", body: {
        "data" => [
          { "id" => "9001", "text" => "any cooking class near Rochester?", "author_id" => "42", "created_at" => "2026-07-02T12:00:00Z" },
          { "id" => "9002", "text" => "   ", "author_id" => "43", "created_at" => "2026-07-02T13:00:00Z" }
        ],
        "includes" => { "users" => [ { "id" => "42", "username" => "foodie" }, { "id" => "43", "username" => "blank" } ] },
        "meta" => { "result_count" => 2 }
      } }
    end

    posts = X::UserClient.new(@account).search_recent('cooking class (Rochester OR "Finger Lakes")')

    assert_includes captured, "search/recent"
    assert_includes captured, "expansions="
    assert_equal 1, posts.size
    p = posts.first
    assert_equal "9001", p[:external_id]
    assert_equal "foodie", p[:author]
    assert_equal "https://x.com/foodie/status/9001", p[:url]
    assert p[:posted_at].present?
  end

  test "empty query returns [] without a call" do
    called = false
    X::UserClient.http_stub = ->(*) { called = true; { status: "200", body: {} } }
    assert_equal [], X::UserClient.new(@account).search_recent("")
    assert_not called
  end

  test "non-200 (e.g. tier lacks recent search) degrades to []" do
    X::UserClient.http_stub = ->(*) { { status: "403", body: { "title" => "Unsupported Authentication" } } }
    assert_equal [], X::UserClient.new(@account).search_recent("cooking class")
  end

  test "a missing-handle tweet still returns, with a nil url" do
    X::UserClient.http_stub = lambda do |_m, _u, _p, _b|
      { status: "200", body: {
        "data" => [ { "id" => "7", "text" => "hi", "author_id" => "99", "created_at" => "2026-07-02T12:00:00Z" } ],
        "includes" => { "users" => [] }
      } }
    end
    posts = X::UserClient.new(@account).search_recent("cooking class")
    assert_equal 1, posts.size
    assert_nil posts.first[:author]
    assert_nil posts.first[:url]
  end
end

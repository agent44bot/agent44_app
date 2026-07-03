require "test_helper"
require "ostruct"

# LeadScout scores a post + drafts a reply. The Anthropic call is stubbed; we
# assert JSON parsing, score clamping, dash stripping, and cost logging.
class LeadScoutTest < ActiveSupport::TestCase
  setup do
    @ws = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = User.create!(email_address: "ls-#{SecureRandom.hex(4)}@example.com") }
  end

  teardown { SocialAi::LeadScout.stub = nil }

  def stub_json(hash)
    SocialAi::LeadScout.stub = lambda do |candidate:|
      OpenStruct.new(content: [ OpenStruct.new(text: hash.to_json) ],
                     usage: OpenStruct.new(input_tokens: 200, output_tokens: 90))
    end
  end

  def candidate
    { text: "Any good cooking classes near Canandaigua?", author: "foodie.bsky.social", platform: "bluesky" }
  end

  test "parses score, reason and reply, and logs the call" do
    stub_json("score" => 88, "reason" => "local, asking for classes", "reply" => "We'd love to have you!")
    r = SocialAi::LeadScout.new(workspace: @ws).evaluate(candidate)
    assert_equal 88, r.score
    assert_match "local", r.reason
    assert_match "love to have you", r.reply
    assert_equal 1, AiCallLog.where(source: "nyk_social_scout").count
  end

  test "clamps an out-of-range score and strips dashes" do
    stub_json("score" => 240, "reason" => "great", "reply" => "Join us for a class — it's fun")
    r = SocialAi::LeadScout.new(workspace: @ws).evaluate(candidate)
    assert_equal 100, r.score
    assert_not_includes r.reply, "—"
    assert_match "class, it's fun", r.reply
  end

  test "returns nil on unparseable output" do
    SocialAi::LeadScout.stub = ->(candidate:) { OpenStruct.new(content: [ OpenStruct.new(text: "not json") ], usage: OpenStruct.new(input_tokens: 1, output_tokens: 1)) }
    assert_nil SocialAi::LeadScout.new(workspace: @ws).evaluate(candidate)
  end

  test "an error returns nil rather than raising" do
    SocialAi::LeadScout.stub = ->(candidate:) { raise "boom" }
    assert_nil SocialAi::LeadScout.new(workspace: @ws).evaluate(candidate)
  end
end

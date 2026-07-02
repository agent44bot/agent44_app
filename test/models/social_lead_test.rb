require "test_helper"

class SocialLeadTest < ActiveSupport::TestCase
  setup do
    @ws = Workspace.create!(name: "Lead WS", slug: "lead-#{SecureRandom.hex(4)}",
                            owner: User.create!(email_address: "lead-#{SecureRandom.hex(4)}@example.com"))
  end

  def build_lead(**attrs)
    @ws.social_leads.build({ platform: "bluesky", external_id: "at://x/1", text: "hi", status: "new" }.merge(attrs))
  end

  test "requires platform, external_id, text and a valid status/platform" do
    assert build_lead.valid?
    assert_not build_lead(platform: nil).valid?
    assert_not build_lead(platform: "instagram").valid?
    assert_not build_lead(external_id: nil).valid?
    assert_not build_lead(text: "").valid?
    assert_not build_lead(status: "weird").valid?
  end

  test "external_id is unique per workspace + platform" do
    build_lead(external_id: "at://dup").save!
    dup = build_lead(external_id: "at://dup")
    assert_not dup.valid?
    # Same id on a different platform is fine.
    assert build_lead(external_id: "at://dup", platform: "reddit").valid?
  end

  test "new_leads returns only new, highest score first" do
    build_lead(external_id: "a", score: 50).save!
    build_lead(external_id: "b", score: 90).save!
    build_lead(external_id: "c", score: 99, status: "dismissed").save!
    assert_equal %w[b a], @ws.social_leads.new_leads.map(&:external_id)
  end
end

require "test_helper"

class EchoMailerTest < ActionMailer::TestCase
  setup do
    @owner = User.create!(email_address: "echo-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @ws = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @owner }
  end

  def lead(score: 95, **attrs)
    @ws.social_leads.create!({
      platform: "x", external_id: SecureRandom.hex(6), author: "News_8",
      text: "A $24 million culinary arts facility is coming to Canandaigua.",
      url: "https://x.com/News_8/status/1", posted_at: 3.days.ago, score: score,
      reason: "Directly mentions New York Kitchen.", draft_reply: "We are so excited about this project!",
      matched_query: "(\"New York Kitchen\")", status: "new"
    }.merge(attrs))
  end

  test "renders the post, why, suggested reply, and links" do
    mail = EchoMailer.new_leads(workspace: @ws, leads: [ lead ], recipient: "botwhisperer@hey.com")

    assert_equal [ "botwhisperer@hey.com" ], mail.to
    assert_match "1 new conversation for NY Kitchen", mail.subject
    assert_match "X", mail.subject

    body = mail.html_part ? mail.html_part.body.to_s : mail.body.to_s
    assert_match "culinary arts facility", body
    assert_match "Directly mentions New York Kitchen", body
    assert_match "We are so excited about this project", body
    assert_match "https://x.com/News_8/status/1", body
    assert_match "https://agent44labs.com/nykitchen/social", body
  end

  test "one email covers every lead, highest score first" do
    low  = lead(score: 62, text: "Finger Lakes wine tasting was great")
    high = lead(score: 95, text: "Good times at NY Kitchen")

    mail = EchoMailer.new_leads(workspace: @ws, leads: [ low, high ], recipient: "a@example.com")

    assert_match "2 new conversations for NY Kitchen", mail.subject
    body = mail.html_part ? mail.html_part.body.to_s : mail.body.to_s
    assert body.index("Good times at NY Kitchen") < body.index("Finger Lakes wine tasting was great"),
           "higher-scoring lead should come first"
  end

  test "links a non-NYK workspace to its generic Echo page" do
    other = Workspace.create!(slug: "gems-of-eden-#{SecureRandom.hex(3)}", name: "Gems of Eden", owner: @owner)
    l = other.social_leads.create!(platform: "bluesky", external_id: "b1", author: "grower",
                                   text: "microgreens in Greece NY", url: "https://bsky.app/p/1",
                                   posted_at: 1.day.ago, score: 80, status: "new")

    mail = EchoMailer.new_leads(workspace: other, leads: [ l ], recipient: "a@example.com")
    body = mail.html_part ? mail.html_part.body.to_s : mail.body.to_s
    assert_match "https://agent44labs.com/workspaces/#{other.slug}/social", body
  end

  test "a member gets an explicit how-to-turn-off block, an unsubscribe link, and the List-Unsubscribe headers" do
    membership = @ws.memberships.find_or_create_by!(user: @owner) { |m| m.role = "owner" }

    mail = EchoMailer.new_leads(workspace: @ws, leads: [ lead ], recipient: @owner.email_address, membership: membership)

    body = mail.html_part ? mail.html_part.body.to_s : mail.body.to_s
    assert_match "Don't want this email?", body
    assert_match "Turn off Echo emails", body
    assert_match "https://agent44labs.com/settings", body

    url = "https://agent44labs.com/echo_email/unsubscribe/#{membership.echo_unsubscribe_token}"
    assert_includes body, url
    assert_equal "<#{url}>", mail["List-Unsubscribe"].to_s
    assert_equal "List-Unsubscribe=One-Click", mail["List-Unsubscribe-Post"].to_s
  end

  test "a non-member address still gets the Settings route, but no unsubscribe link or header" do
    mail = EchoMailer.new_leads(workspace: @ws, leads: [ lead ], recipient: "agency@example.com")

    body = mail.html_part ? mail.html_part.body.to_s : mail.body.to_s
    assert_match "Don't want this email?", body
    assert_no_match(/echo_email\/unsubscribe/, body)
    assert_nil mail["List-Unsubscribe"]
  end
end

require "test_helper"
require "ostruct"

# ClassPromoDraftJob picks a bookable NYK class, drafts an Echo post, and pushes
# Rich a deep link to review it. The AI writer is stubbed (never hits Anthropic)
# and APNs never reaches Apple (users have no DeviceToken rows), so we assert on
# the WorkspaceDraft + Notification the job creates.
class ClassPromoDraftJobTest < ActiveJob::TestCase
  setup do
    Setting.delete_all
    Notification.delete_all
    @rich = User.create!(email_address: "promo-#{SecureRandom.hex(4)}@example.com", role: "admin")
    Setting.set("class_promo:user_ids", @rich.id.to_s)
    @nyk = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @rich }
    @nyk.social_accounts.create!(platform: "x", external_id: "promo-x", handle: "@nyk",
                                 connected_by: @rich, access_token: "AT", refresh_token: "RT",
                                 token_expires_at: 2.hours.from_now, status: "active")
    # Deterministic copy so tests never touch the API.
    KitchenAi::ClassPromoWriter.stub = lambda do |event:|
      OpenStruct.new(content: [ OpenStruct.new(text: "Come cook #{event.name}! Book now. #FingerLakes") ],
                     usage: OpenStruct.new(input_tokens: 100, output_tokens: 40))
    end
  end

  teardown { KitchenAi::ClassPromoWriter.stub = nil }

  def run_job(force: false, at: Time.zone.parse("#{Date.current} 14:30"))
    job = ClassPromoDraftJob.new
    def job.dice_roll = 0.0
    travel_to(at) { job.perform(force: force) }
  end

  def snapshot_with(events)
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    list = events.is_a?(Array) ? events : [ events ]
    list.each { |attrs| snap.kitchen_events.create!(default_event.merge(attrs)) }
    snap
  end

  def default_event
    { url: "https://tock/e-#{SecureRandom.hex(3)}", name: "Pasta Night",
      start_at: 3.days.from_now, spots_left: 8, capacity: 12,
      price: "75.00", availability: "available" }
  end

  test "drafts a promo post and pushes a deep link to it" do
    snapshot_with(name: "Wine Country Cooking", url: "https://tock/wine")
    run_job

    draft = WorkspaceDraft.last
    assert draft, "expected an Echo draft"
    assert_equal @rich, draft.author
    assert_equal "draft", draft.status
    assert_equal [ "x" ], draft.target_platforms
    assert_equal "https://tock/wine", draft.source_url
    assert_match "Wine Country Cooking", draft.body

    n = Notification.last
    assert_equal "sam", n.source
    assert_equal @rich, n.user
    assert_equal "/workspaces/nykitchen/drafts/#{draft.id}/edit", n.url
    assert_equal 1, Setting.counter("class_promo:sent:#{Date.current.iso8601}")
  end

  test "no recipients -> nothing happens" do
    Setting.set("class_promo:user_ids", "")
    snapshot_with({})
    run_job
    assert_equal 0, WorkspaceDraft.count
    assert_equal 0, Notification.count
  end

  test "skips sold-out and private events, promotes a bookable one" do
    snapshot_with([
      { name: "Sold Out Class",  url: "https://tock/so",   availability: "SoldOut", spots_left: 0 },
      { name: "Reserved for Private Event", url: "https://tock/priv" },
      { name: "Open Class",      url: "https://tock/open" }
    ])
    run_job
    assert_equal 1, WorkspaceDraft.count
    assert_equal "https://tock/open", WorkspaceDraft.last.source_url
  end

  test "ignores classes beyond the two-week window" do
    snapshot_with(name: "Way Out", url: "https://tock/far", start_at: 30.days.from_now)
    run_job
    assert_equal 0, WorkspaceDraft.count
    assert_equal 0, Notification.count
  end

  test "does not re-promote a class that already has an open draft" do
    snapshot_with(name: "Solo Class", url: "https://tock/solo")
    run_job
    assert_equal 1, WorkspaceDraft.count
    # Same snapshot, cooldown irrelevant: an open draft blocks a duplicate.
    run_job(force: true)
    assert_equal 1, WorkspaceDraft.count, "should not stack a second draft for the same class"
  end

  test "falls back to a template when the writer returns nothing" do
    KitchenAi::ClassPromoWriter.stub = ->(event:) { OpenStruct.new(content: [ OpenStruct.new(text: "") ], usage: OpenStruct.new(input_tokens: 1, output_tokens: 1)) }
    snapshot_with(name: "Bagel Workshop", url: "https://tock/bagel", price: "85.00", spots_left: 3)
    run_job
    body = WorkspaceDraft.last.body
    assert_match "Bagel Workshop", body
    assert_match "New York Kitchen, Canandaigua", body
    assert_match "Only 3 seats left", body
  end

  test "respects the daily budget" do
    snapshot_with({})
    Setting.set("class_promo:sent:#{Date.current.iso8601}", "2")
    run_job
    assert_equal 0, Notification.count
  end

  test "quiet outside the send window" do
    snapshot_with({})
    run_job(at: Time.zone.parse("#{Date.current} 22:00"))
    assert_equal 0, Notification.count
  end

  test "force bypasses window and budget for manual testing" do
    snapshot_with({})
    Setting.set("class_promo:sent:#{Date.current.iso8601}", "2")
    run_job(force: true, at: Time.zone.parse("#{Date.current} 23:00"))
    assert_equal 1, Notification.count
  end

  test "never promotes a manual camp class" do
    # Camps live in their own table (KitchenManualClass), not kitchen_events,
    # and must not get social promotion. With only a camp on the schedule and
    # no scraped class, the job finds nothing to draft.
    KitchenSnapshot.create!(taken_on: Date.current) # empty snapshot, no events
    KitchenManualClass.create!(name: "Kids Summer Camp", start_at: 3.days.from_now,
                               created_by: @rich)
    run_job(force: true)
    assert_equal 0, WorkspaceDraft.count
    assert_equal 0, Notification.count
  end

  test "nothing to promote -> no push, no draft" do
    snapshot_with(name: "Sold Out", url: "https://tock/so", availability: "SoldOut", spots_left: 0)
    run_job
    assert_equal 0, WorkspaceDraft.count
    assert_equal 0, Notification.count
  end
end

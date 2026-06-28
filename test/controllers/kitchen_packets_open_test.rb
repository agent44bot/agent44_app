require "test_helper"
require "ostruct"

# Lazy on-open recipe drafting: opening a class with no recipe either carries
# forward a prior run ($0), drafts one with AI (when allowed), or falls back to
# the manual form. The extractor is stubbed (never hit the Anthropic API).
class KitchenPacketsOpenTest < ActionDispatch::IntegrationTest
  GENERATED = {
    "recipes" => [ {
      "title" => "Baby Back Ribs",
      "ingredients" => [ { "qty" => "2 lb", "station_qty" => "1 lb", "item" => "Baby back ribs", "section" => nil } ],
      "directions" => [ { "section" => nil, "steps" => [ "Rub.", "Smoke." ] } ]
    } ],
    "equipment" => [ "Sheet pan", "Tongs" ]
  }.freeze

  setup do
    @user = User.create!(email_address: "open-#{SecureRandom.hex(4)}@example.com", role: "user")
    sign_in_as(@user)
    Setting.delete_key("nyk:auto_recipe_on_open")
  end

  teardown { KitchenAi::RecipeExtractor.stub = nil }

  # A latest snapshot with one class. `when_at`/`cap`/`left` tune the cost guard.
  def class_event(name:, url:, when_at: 2.weeks.from_now, cap: nil, left: nil)
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    snap.kitchen_events.create!(name: name, url: url, start_at: when_at,
                                availability: "InStock", capacity: cap, spots_left: left)
    url
  end

  def stub_generate_success
    text = OpenStruct.new(text: GENERATED.to_json)
    KitchenAi::RecipeExtractor.stub = ->(messages:) {
      OpenStruct.new(content: [ text ], usage: OpenStruct.new(input_tokens: 120, output_tokens: 300))
    }
  end

  def stub_must_not_call
    KitchenAi::RecipeExtractor.stub = ->(messages:) { raise "should not have called AI" }
  end

  test "first open of a near-term class drafts with AI, links it, lands on edit" do
    stub_generate_success
    url = class_event(name: "Baby Back Ribs Class 7/2/26", url: "https://nyk/event/ribs-7-2/")

    assert_difference -> { KitchenPacket.count }, 1 do
      get open_nyk_packet_path(event_url: url, event_name: "Baby Back Ribs Class 7/2/26")
    end
    packet = KitchenPacket.for_event_url(url)
    assert_redirected_to edit_nyk_packet_path(packet)
    assert_equal "nyk_recipe_generate", AiCallLog.last.source
    assert packet.extract_cost_cents.to_i.positive?
    assert_equal [ "Sheet pan", "Tongs" ], packet.equipment, "carries the generated equipment list"
  end

  test "re-opening a class with a recipe never re-bills" do
    url = class_event(name: "Knife Skills 7/4/26", url: "https://nyk/event/knife-7-4/")
    existing = KitchenPacket.create!(title: "Knife Skills", data: { "recipes" => GENERATED["recipes"] })
    existing.attach_to!(url)

    stub_must_not_call
    assert_no_difference -> { AiCallLog.count } do
      get open_nyk_packet_path(event_url: url, event_name: "Knife Skills 7/4/26")
    end
    assert_redirected_to edit_nyk_packet_path(existing)
  end

  test "a recurring class carries forward the last run as a free, independent copy" do
    prior = KitchenPacket.create!(
      title: "Korean Barbecue Class 6/20/26",
      data: { "recipes" => GENERATED["recipes"], "equipment" => [ "Grill pan" ] }
    )
    prior.attach_to!("https://nyk/event/korean-6-20/")
    url = class_event(name: "Korean Barbecue Class 7/3/26", url: "https://nyk/event/korean-7-3/")

    stub_must_not_call
    assert_no_difference -> { AiCallLog.count } do
      assert_difference -> { KitchenPacket.count }, 1 do
        get open_nyk_packet_path(event_url: url, event_name: "Korean Barbecue Class 7/3/26")
      end
    end
    copy = KitchenPacket.for_event_url(url)
    assert_not_equal prior, copy, "a new independent copy, not the shared prior packet"
    assert_equal [ "Grill pan" ], copy.equipment, "equipment carries on the copy"
    assert_equal 1, prior.reload.links.count, "the prior run's packet keeps only its own link"
    assert KitchenPacketLink.find_by(event_url: url).auto, "carried-forward link is badged auto"
  end

  test "far-future, not-selling class falls back to the manual form with no AI" do
    stub_must_not_call
    url = class_event(name: "Holiday Cookies 12/15/26", url: "https://nyk/event/cookies-12-15/",
                      when_at: 120.days.from_now)
    assert_no_difference [ "KitchenPacket.count", "AiCallLog.count" ] do
      get open_nyk_packet_path(event_url: url, event_name: "Holiday Cookies 12/15/26")
    end
    assert_redirected_to new_nyk_packet_path(event_url: url, event_name: "Holiday Cookies 12/15/26")
  end

  test "a far-future class that is already selling still drafts" do
    stub_generate_success
    url = class_event(name: "Holiday Cookies 12/15/26", url: "https://nyk/event/cookies-sell/",
                      when_at: 120.days.from_now, cap: 12, left: 8) # 4 sold
    assert_difference -> { KitchenPacket.count }, 1 do
      get open_nyk_packet_path(event_url: url, event_name: "Holiday Cookies 12/15/26")
    end
    assert_equal "nyk_recipe_generate", AiCallLog.last.source
  end

  test "the toggle off falls back to the manual form with no AI" do
    Setting.set("nyk:auto_recipe_on_open", "false")
    stub_must_not_call
    url = class_event(name: "Baby Back Ribs Class 7/2/26", url: "https://nyk/event/ribs-off/")
    assert_no_difference [ "KitchenPacket.count", "AiCallLog.count" ] do
      get open_nyk_packet_path(event_url: url, event_name: "Baby Back Ribs Class 7/2/26")
    end
    assert_redirected_to new_nyk_packet_path(event_url: url, event_name: "Baby Back Ribs Class 7/2/26")
  end
end

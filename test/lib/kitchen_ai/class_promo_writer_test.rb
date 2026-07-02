require "test_helper"
require "ostruct"

# ClassPromoWriter turns one class into a short promo post. The Anthropic call
# is stubbed; we assert the copy comes back, is logged, and that em/en dashes
# are stripped (house rule for AI-generated copy).
class ClassPromoWriterTest < ActiveSupport::TestCase
  setup do
    @snap  = KitchenSnapshot.create!(taken_on: Date.current)
    @event = @snap.kitchen_events.create!(
      url: "https://tock/curry", name: "Perfect Curry Class",
      start_at: 5.days.from_now, spots_left: 12, capacity: 12,
      price: "85.00", availability: "available"
    )
  end

  teardown { KitchenAi::ClassPromoWriter.stub = nil }

  def stub_reply(text)
    KitchenAi::ClassPromoWriter.stub = lambda do |event:|
      OpenStruct.new(content: [ OpenStruct.new(text: text) ],
                     usage: OpenStruct.new(input_tokens: 200, output_tokens: 80))
    end
  end

  test "returns the model copy and logs the call" do
    stub_reply("Cook up something special! Perfect Curry Class 7/6. Book now. #FingerLakes")
    body = KitchenAi::ClassPromoWriter.new.write(@event)
    assert_match "Perfect Curry Class", body
    assert_equal 1, AiCallLog.where(source: "nyk_enhance").count
  end

  test "strips em and en dashes from the copy" do
    stub_reply("Perfect Curry Class — 7/6 – book now! #Canandaigua")
    body = KitchenAi::ClassPromoWriter.new.write(@event)
    assert_not_includes body, "—"
    assert_not_includes body, "–"
    assert_match "Class, 7/6, book now!", body
  end

  test "blank copy returns nil so the caller can fall back" do
    stub_reply("   ")
    assert_nil KitchenAi::ClassPromoWriter.new.write(@event)
  end

  test "an error in the call returns nil rather than raising" do
    KitchenAi::ClassPromoWriter.stub = ->(event:) { raise "boom" }
    assert_nil KitchenAi::ClassPromoWriter.new.write(@event)
  end
end

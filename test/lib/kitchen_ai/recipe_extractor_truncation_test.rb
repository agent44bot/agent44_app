require "test_helper"
require "ostruct"

# When a big multi-recipe PDF makes the model hit the token cap, the reply is
# cut off and parses to nothing. The extractor should say the document was too
# LONG (so the fix is a shorter file), not the misleading "could not find a
# recipe". No network: the class-level stub stands in for the API.
class RecipeExtractorTruncationTest < ActiveSupport::TestCase
  teardown { KitchenAi::RecipeExtractor.stub = nil }

  # A stub API response: `text` is the (possibly truncated) model output and
  # `stop_reason` mirrors the real field the extractor checks.
  def stub_response(text:, stop_reason:)
    KitchenAi::RecipeExtractor.stub = lambda do |messages:|
      OpenStruct.new(
        content: [ OpenStruct.new(text: text) ],
        usage: OpenStruct.new(input_tokens: 100, output_tokens: 4000),
        stop_reason: stop_reason
      )
    end
  end

  test "truncated? is true only when the model hit the token cap" do
    ex = KitchenAi::RecipeExtractor.new
    assert ex.send(:truncated?, OpenStruct.new(stop_reason: "max_tokens"))
    assert_not ex.send(:truncated?, OpenStruct.new(stop_reason: "end_turn"))
    assert_not ex.send(:truncated?, Object.new) # no stop_reason -> safe
  end

  test "a truncated reply reports the document was too long, not 'not found'" do
    stub_response(text: '{"recipes": [{"title": "Pasta", "ingredients": [{"qty": "2 c', stop_reason: "max_tokens")
    r = KitchenAi::RecipeExtractor.new.extract(text: "big menu")
    assert_not r.ok?
    assert_match(/too long/i, r.error)
    assert_match(/split|shorter|paste/i, r.error)
  end

  test "an un-truncated unparseable reply keeps the 'could not find a recipe' message" do
    stub_response(text: "sorry, I cannot help with that", stop_reason: "end_turn")
    r = KitchenAi::RecipeExtractor.new.extract(text: "not a recipe")
    assert_not r.ok?
    assert_match(/could not find a recipe/i, r.error)
  end
end

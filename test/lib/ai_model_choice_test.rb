require "test_helper"

class AiModelChoiceTest < ActiveSupport::TestCase
  test "resolve returns the call site default when no override is saved" do
    assert_equal "claude-opus-4-8",
                 AiModelChoice.resolve("nyk_grocery_list", default: "claude-opus-4-8")
  end

  test "resolve returns the saved override's model id" do
    AiModelChoice.set("nyk_grocery_list", "haiku")
    assert_equal "claude-haiku-4-5-20251001",
                 AiModelChoice.resolve("nyk_grocery_list", default: "claude-opus-4-8")
  end

  test "selected_key falls back to the feature default, then to a saved override" do
    assert_equal "opus", AiModelChoice.selected_key("nyk_grocery_list") # documented default
    assert_equal "haiku", AiModelChoice.selected_key("nyk_ask")
    AiModelChoice.set("nyk_ask", "sonnet")
    assert_equal "sonnet", AiModelChoice.selected_key("nyk_ask")
  end

  test "set rejects an unknown model key" do
    assert_raises(ArgumentError) { AiModelChoice.set("nyk_grocery_list", "gpt") }
  end

  test "controllable? is true for in-app features and false for the external autopost" do
    assert AiModelChoice.controllable?("nyk_grocery_list")
    assert_not AiModelChoice.controllable?("nyk_x_autopost")
  end

  test "every selectable model is priced in AiCallLog::RATES" do
    AiModelChoice::OPTIONS.each_value do |opt|
      assert AiCallLog::RATES.key?(opt[:id]), "#{opt[:id]} missing from RATES"
    end
  end
end

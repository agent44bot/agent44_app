require "test_helper"

class WorkspacePosts::FitterTest < ActiveSupport::TestCase
  Fitter = WorkspacePosts::Fitter

  test "leaves text under the limit untouched" do
    text = "Short and sweet."
    assert_equal text, Fitter.fit(text, limit: 280)
  end

  test "drops trailing hashtags first to make it fit" do
    text = "Join our cooking class tonight! #NYKitchen #FingerLakes #CookingClass #Foodie"
    fitted = Fitter.fit(text, limit: 50)
    assert_operator fitted.length, :<=, 50
    assert_includes fitted, "Join our cooking class tonight!"
    refute_includes fitted, "#Foodie" # last hashtag dropped
  end

  test "truncates the body but preserves a trailing link" do
    url  = "https://nykitchen.com/event/a-very-long-event-slug-here/"
    text = "#{"word " * 100}\n#{url}"
    fitted = Fitter.fit(text, limit: 120)
    assert_operator fitted.length, :<=, 120
    assert_includes fitted, url, "the reservation link must survive truncation"
    assert_includes fitted, "…"
  end

  test "counts X links as 23 chars so a long URL alone does not trip the limit" do
    url  = "https://nykitchen.com/event/#{"x" * 200}/" # >200 literal chars
    text = "Reserve your spot! #{url}"
    # Literally this is >200 chars, but on X the link counts as 23.
    fitted = Fitter.fit(text, limit: 280, url_weight: 23)
    assert_equal text, fitted, "should not truncate: weighted length is well under 280"
  end

  test "plain-truncates with an ellipsis when there is no link" do
    text = "a" * 400
    fitted = Fitter.fit(text, limit: 100)
    assert_operator fitted.length, :<=, 100
    assert fitted.end_with?("…")
  end

  test "X tweet_length counts a link as 23 regardless of real length" do
    url = "https://nykitchen.com/event/#{"x" * 100}/"
    assert_operator url.length, :>, 100
    assert_equal "Book now ".length + 23, X::UserClient.tweet_length("Book now #{url}")
  end
end

require "test_helper"

class NykChangelogTest < ActiveSupport::TestCase
  test "parses the committed changelog into dated, owner-facing notes" do
    all = NykChangelog.recent(since: Date.new(2000, 1, 1), limit: 50)
    assert all.any?, "expected the committed config/nyk_changelog.yml to have entries"
    all.each do |e|
      assert e[:date].is_a?(Date), "each entry has a Date"
      assert e[:note].present?,    "each entry has a note"
    end
  end

  test "returns entries newest-first" do
    dates = NykChangelog.recent(since: Date.new(2000, 1, 1), limit: 50).map { |e| e[:date] }
    assert_equal dates.sort.reverse, dates
  end

  test "excludes entries older than `since` and caps at limit" do
    assert_empty NykChangelog.recent(since: Date.current + 365)
    assert_operator NykChangelog.recent(since: Date.new(2000, 1, 1), limit: 2).size, :<=, 2
  end
end

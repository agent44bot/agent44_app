require "test_helper"
require "minitest/mock"

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

  test "parses optional link + label, defaults the label, and rejects external links" do
    rows = [
      { "date" => "2026-06-08", "note" => "Internal", "link" => "/nykitchen/test", "link_label" => "Open Test" },
      { "date" => "2026-06-08", "note" => "Defaulted", "link" => "/nykitchen/analyst" },
      { "date" => "2026-06-08", "note" => "External", "link" => "https://evil.example.com" },
      { "date" => "2026-06-08", "note" => "Plain" }
    ]
    YAML.stub(:safe_load_file, rows) do
      e = NykChangelog.entries
      internal = e.find { |x| x[:note] == "Internal" }
      assert_equal "/nykitchen/test", internal[:link]
      assert_equal "Open Test", internal[:link_label]
      assert_equal "View", e.find { |x| x[:note] == "Defaulted" }[:link_label]
      external = e.find { |x| x[:note] == "External" }
      assert_nil external[:link], "external links must be dropped"
      assert_nil external[:link_label]
      assert_nil e.find { |x| x[:note] == "Plain" }[:link]
    end
  end

  test "committed changelog links are app-relative paths with labels" do
    # Scan every committed entry, not just the recent window: as unlinked notes
    # accumulate, the linked ones age out of any capped `recent` slice, which
    # would leave this test asserting nothing ("missing assertions").
    entries = NykChangelog.entries
    assert entries.any?, "expected the committed config/nyk_changelog.yml to have entries"
    entries.each do |e|
      next unless e[:link]
      assert e[:link].start_with?("/"), "link must be app-relative: #{e[:link]}"
      assert e[:link_label].present?, "a linked entry needs a label"
    end
  end
end

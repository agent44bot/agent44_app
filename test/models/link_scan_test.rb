require "test_helper"

class LinkScanTest < ActiveSupport::TestCase
  setup do
    # for_url derives the token from the URL, so no literal token string here
    # (a hard-coded token: "..." trips gitleaks' generic-secret rule).
    @link = TrackedLink.for_url("https://nykitchen.com/calendar")
  end

  def scan(source)
    @link.link_scans.create!(scanned_at: Time.current, source: source)
  end

  test "from_display returns only tasting-room monitor scans" do
    display = scan("display")
    scan(nil)
    scan("flyer")
    assert_equal [ display.id ], LinkScan.from_display.pluck(:id)
  end

  test "from_flyer includes NULL-source scans (the untagged printed-flyer case)" do
    # The whole point of the scope: a plain where.not(source: "display") would
    # drop this NULL row in SQL, silently undercounting billable flyer scans.
    nil_scan   = scan(nil)
    flyer_scan = scan("flyer")
    scan("display")
    assert_equal [ nil_scan.id, flyer_scan.id ].sort, LinkScan.from_flyer.pluck(:id).sort
  end

  test "from_flyer and from_display partition all scans with no overlap" do
    scan(nil)
    scan("flyer")
    scan("display")
    all = LinkScan.count
    assert_equal all, LinkScan.from_flyer.count + LinkScan.from_display.count
    assert_empty LinkScan.from_flyer.where(id: LinkScan.from_display).to_a
  end

  test "from_stall returns only stall-poster scans, and they still count as billable flyers" do
    stall = scan("stall")
    scan("flyer")
    scan("display")
    assert_equal [ stall.id ], LinkScan.from_stall.pluck(:id)
    # stall is a printed poster, so it bills like a flyer (only the screen is exempt)
    assert_includes LinkScan.from_flyer.pluck(:id), stall.id
  end

  test "source_label maps each source, with untagged NULL as a legacy flyer" do
    assert_equal "Screen", LinkScan.source_label("display")
    assert_equal "Front-desk flyer", LinkScan.source_label("flyer")
    assert_equal "Stall flyer", LinkScan.source_label("stall")
    assert_equal "Flyer (untagged)", LinkScan.source_label(nil)
  end

  test "billed_source? exempts only the screen" do
    assert_not LinkScan.billed_source?("display")
    [ "flyer", "stall", nil ].each { |s| assert LinkScan.billed_source?(s), "#{s.inspect} should bill" }
  end
end

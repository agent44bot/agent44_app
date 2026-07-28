require "test_helper"
require "minitest/mock"

class DeputyClientTest < ActiveSupport::TestCase
  # One Deputy Roster/QUERY row (epoch StartTime/EndTime + joined objects).
  def roster(start_epoch, hours, employee_id, name, area)
    {
      "Employee"              => employee_id,
      "StartTime"             => start_epoch,
      "EndTime"               => start_epoch + (hours * 3600).to_i,
      "EmployeeObject"        => name ? { "DisplayName" => name } : nil,
      "OperationalUnitObject" => { "OperationalUnitName" => area }
    }
  end

  test "weekly_hours groups by employee, splits open shifts, totals by area" do
    base = 1_700_000_000
    rows = [
      roster(base,           5.0, 11, "Alice A", "Culinary EA"),
      roster(base + 100_000, 3.0, 11, "Alice A", "Culinary EA"),
      roster(base,           4.0, 22, "Bob B",   "Dishwasher"),
      roster(base,           2.0, 0,  nil,       "Beverage EA") # unfilled open shift
    ]
    result = DeputyClient.stub(:post, rows) do
      DeputyClient.weekly_hours(Date.new(2026, 7, 20), Date.new(2026, 7, 26))
    end

    assert_equal [ { employee: "Alice A", hours: 8.0 }, { employee: "Bob B", hours: 4.0 } ], result[:rows]
    assert_equal 12.0, result[:total]
    assert_equal 2.0,  result[:open_hours], "open/unassigned shift stays out of the staffed total"
    assert_equal({ "Culinary EA" => 8.0, "Dishwasher" => 4.0, "Beverage EA" => 2.0 }, result[:by_area])
    assert_equal 4, result[:shift_count]
  end

  test "weekly_hours skips rows without valid start/end times" do
    rows = [ { "Employee" => 1, "StartTime" => nil, "EndTime" => nil,
               "EmployeeObject" => { "DisplayName" => "X" } } ]
    result = DeputyClient.stub(:post, rows) do
      DeputyClient.weekly_hours(Date.new(2026, 7, 20), Date.new(2026, 7, 26))
    end
    assert_empty result[:rows]
    assert_equal 0, result[:shift_count]
  end

  test "configured? tracks token presence" do
    DeputyClient.stub(:token, nil)   { assert_not DeputyClient.configured? }
    DeputyClient.stub(:token, "abc") { assert DeputyClient.configured? }
  end

  test "post raises a friendly error (no HTTP) when unconfigured" do
    DeputyClient.stub(:token, nil) do
      err = assert_raises(DeputyClient::Error) { DeputyClient.post("resource/Roster/QUERY", {}) }
      assert_match(/not configured/i, err.message)
    end
  end

  test "approve_url points at the Deputy approve screen" do
    assert_match %r{\Ahttps://.+\.deputy\.com/#/approve-v2\z}, DeputyClient.approve_url
  end

  test "active_timesheet_count excludes discarded and 0-minute ghost timesheets" do
    rows = [
      { "Id" => 1, "Discarded" => nil, "TotalTime" => 5 },                                # real
      { "Id" => 2, "Discarded" => "2026-07-23T00:00:00-04:00", "TotalTime" => 5 },        # discarded
      { "Id" => 3, "TotalTime" => 3 },                                                    # real
      { "Id" => 4, "TotalTime" => 0 }                                                    # ghost (0 min)
    ]
    DeputyClient.stub(:post, rows) do
      assert_equal 2, DeputyClient.active_timesheet_count(Date.new(2026, 7, 20), Date.new(2026, 7, 26))
    end
  end

  test "timesheet_status groups by employee, counts approved vs pending, excludes ghosts" do
    rows = [
      { "EmployeeObject" => { "DisplayName" => "Alice" }, "TimeApproved" => true,  "TotalTime" => 5, "Discarded" => nil },
      { "EmployeeObject" => { "DisplayName" => "Alice" }, "TimeApproved" => false, "TotalTime" => 3, "Discarded" => nil },
      { "EmployeeObject" => { "DisplayName" => "Bob" },   "TimeApproved" => false, "TotalTime" => 4, "Discarded" => nil },
      { "EmployeeObject" => { "DisplayName" => "Ghost" }, "TimeApproved" => false, "TotalTime" => 0, "Discarded" => nil },                 # ghost
      { "EmployeeObject" => { "DisplayName" => "Gone" },  "TimeApproved" => true,  "TotalTime" => 5, "Discarded" => "2026-07-23T00:00:00-04:00" } # discarded
    ]
    st = DeputyClient.stub(:post, rows) do
      DeputyClient.timesheet_status(Date.new(2026, 7, 20), Date.new(2026, 7, 26))
    end
    assert_equal({ approved: 1, pending: 1, total: 2 }, st[:by_employee]["Alice"])
    assert_equal({ approved: 0, pending: 1, total: 1 }, st[:by_employee]["Bob"])
    assert_nil st[:by_employee]["Ghost"], "0-minute ghost excluded"
    assert_nil st[:by_employee]["Gone"],  "discarded excluded"
    assert_equal 3, st[:total]
    assert_equal 1, st[:approved]
    assert_equal 2, st[:pending]
  end

  test "generate_week_timesheets refuses (no dupes) when timesheets already exist" do
    DeputyClient.stub(:active_timesheet_count, 5) do
      result = DeputyClient.generate_week_timesheets(Date.new(2026, 7, 20), Date.new(2026, 7, 26))
      assert_equal :exists, result[:status]
      assert_equal 5, result[:existing]
    end
  end

  test "generate_week_timesheets creates one per staffed shift, skipping open shifts" do
    base = 1_700_000_000
    rosters = [
      roster(base, 5.0, 11, "Alice A", "Culinary EA"),
      roster(base, 4.0, 22, "Bob B",   "Dishwasher"),
      roster(base, 2.0, 0,  nil,       "Beverage EA") # open/unfilled: skipped
    ]
    DeputyClient.stub(:active_timesheet_count, 0) do
      DeputyClient.stub(:query_roster, rosters) do
        DeputyClient.stub(:post, { "Id" => 999 }) do # every create "succeeds"
          result = DeputyClient.generate_week_timesheets(Date.new(2026, 7, 20), Date.new(2026, 7, 26))
          assert_equal :created, result[:status]
          assert_equal 2, result[:created], "open shift is not timesheeted"
        end
      end
    end
  end
end

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
end

require "test_helper"
require "minitest/mock"

class KitchenHoursTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear # the hours action caches per week; keep tests isolated
    @admin = User.create!(email_address: "hrs-#{SecureRandom.hex(4)}@example.com", role: "admin")
    Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @admin }
    @data = {
      rows:        [ { employee: "Allyn Itterly", hours: 33.5 }, { employee: "Bob B", hours: 4.0 } ],
      total:       37.5,
      open_hours:  2.0,
      by_area:     { "Culinary EA" => 33.5, "Dishwasher" => 4.0 },
      shift_count: 6,
    }
  end

  test "a manager sees the team hours table" do
    sign_in_as(@admin)
    with_deputy(@data) { get nyk_hours_path }
    assert_response :success
    assert_select "h1", /Team hours/
    assert_match "Allyn Itterly", response.body
    assert_match "Export to Excel", response.body
  end

  test "a non-manager gets a 404" do
    sign_in_as(User.create!(email_address: "out-#{SecureRandom.hex(4)}@example.com", role: "user"))
    get nyk_hours_path
    assert_response :not_found
  end

  test "the xlsx export returns a real Excel file" do
    sign_in_as(@admin)
    with_deputy(@data) { get nyk_hours_path(xlsx: 1) }
    assert_response :success
    assert_equal NykHoursXlsx::CONTENT_TYPE, response.media_type
    assert_equal "PK", response.body[0, 2], "xlsx payload should be a zip"
  end

  test "shows a friendly message when Deputy is not connected" do
    sign_in_as(@admin)
    DeputyClient.stub(:configured?, false) { get nyk_hours_path }
    assert_response :success
    assert_match(/not connected/i, response.body)
  end

  test "?week= selects the Mon-Sun week containing that date" do
    sign_in_as(@admin)
    captured = nil
    fake = ->(from, to) { captured = [ from, to ]; @data }
    DeputyClient.stub(:configured?, true) do
      DeputyClient.stub(:weekly_hours, fake) do
        get nyk_hours_path(week: "2026-07-15") # a Wednesday
      end
    end
    assert_equal [ Date.new(2026, 7, 13), Date.new(2026, 7, 19) ], captured
  end

  private

  def with_deputy(data, &blk)
    DeputyClient.stub(:configured?, true) do
      DeputyClient.stub(:weekly_hours, data, &blk)
    end
  end
end

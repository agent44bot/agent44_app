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
      shift_count: 6
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
      DeputyClient.stub(:timesheet_status, { by_employee: {}, total: 0, approved: 0, pending: 0 }) do
        DeputyClient.stub(:weekly_hours, fake) do
          get nyk_hours_path(week: "2026-07-15") # a Wednesday
        end
      end
    end
    assert_equal [ Date.new(2026, 7, 13), Date.new(2026, 7, 19) ], captured
  end

  test "shows the Generate timesheets button when the week has none" do
    sign_in_as(@admin)
    with_deputy(@data, timesheet_count: 0) { get nyk_hours_path }
    assert_response :success
    assert_match "Generate timesheets", response.body
    assert_no_match "Review in Deputy", response.body
  end

  test "shows a Review in Deputy link when timesheets already exist" do
    sign_in_as(@admin)
    with_deputy(@data, timesheet_count: 46) { get nyk_hours_path }
    assert_response :success
    assert_match "Review in Deputy", response.body
    assert_match "46", response.body
    assert_no_match "Generate timesheets", response.body
  end

  test "generate_timesheets creates and redirects with a notice" do
    sign_in_as(@admin)
    DeputyClient.stub(:configured?, true) do
      DeputyClient.stub(:generate_week_timesheets, { status: :created, created: 46 }) do
        post nyk_generate_timesheets_path(week: "2026-07-20")
      end
    end
    assert_redirected_to nyk_hours_path(week: Date.new(2026, 7, 20))
    assert_match(/Created 46 pending timesheets/, flash[:notice])
  end

  test "generate_timesheets makes nothing when timesheets already exist" do
    sign_in_as(@admin)
    DeputyClient.stub(:configured?, true) do
      DeputyClient.stub(:generate_week_timesheets, { status: :exists, existing: 46 }) do
        post nyk_generate_timesheets_path(week: "2026-07-20")
      end
    end
    assert_match(/already exist/i, flash[:alert])
  end

  test "generate_timesheets is manager-only" do
    sign_in_as(User.create!(email_address: "out-#{SecureRandom.hex(4)}@example.com", role: "user"))
    post nyk_generate_timesheets_path(week: "2026-07-20")
    assert_response :not_found
  end

  test "shows per-employee timesheet status badges and an approval summary" do
    sign_in_as(@admin)
    status = {
      by_employee: {
        "Allyn Itterly" => { approved: 5, pending: 0, total: 5 }, # fully approved
        "Bob B"         => { approved: 1, pending: 3, total: 4 } # mixed
      },
      total: 9, approved: 6, pending: 3
    }
    with_deputy(@data, status: status) { get nyk_hours_path }
    assert_response :success
    assert_match "Approved", response.body      # Allyn's badge
    assert_match "Mixed 1/4", response.body     # Bob's badge
    assert_match "6 approved", response.body    # week summary
    assert_match "3 pending", response.body
  end

  private

  # Stubs the Deputy calls the hours page makes: configured?, weekly_hours, and
  # timesheet_status (so no test ever hits the real Deputy API). `status`
  # defaults to an empty week; pass timesheet_count for the total, or a full
  # status hash to exercise the per-employee badges.
  def with_deputy(data, timesheet_count: 0, status: nil, &blk)
    status ||= { by_employee: {}, total: timesheet_count, approved: 0, pending: timesheet_count }
    DeputyClient.stub(:configured?, true) do
      DeputyClient.stub(:weekly_hours, data) do
        DeputyClient.stub(:timesheet_status, status, &blk)
      end
    end
  end
end

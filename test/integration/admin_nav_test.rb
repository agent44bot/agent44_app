require "test_helper"

# The admin layout collapses all destinations into one dropdown menu; the
# Plan link must be present and the bar itself stays minimal.
class AdminNavTest < ActionDispatch::IntegrationTest
  test "admin menu lists all destinations including Plan" do
    admin = User.create!(email_address: "nav-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(admin)
    get admin_dashboard_path
    assert_response :success
    %w[Plan Dashboard Track Scrapers Users Agents Kitchen Notifications Finance].each do |label|
      assert_match %r{>#{label}<}, response.body, "menu should include #{label}"
    end
    assert_match "Visitor Map", response.body
  end

  test "pruned destinations are gone from the menu" do
    admin = User.create!(email_address: "nav-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(admin)
    get admin_dashboard_path
    %w[Posts Videos Chat Lab].each do |label|
      assert_no_match %r{>#{label}<}, response.body, "menu should no longer include #{label}"
    end
    assert_no_match "AI Costs", response.body
  end
end

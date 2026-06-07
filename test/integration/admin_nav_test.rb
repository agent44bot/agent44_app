require "test_helper"

# The admin layout collapses all destinations into one dropdown menu; the
# Plan link must be present and the bar itself stays minimal.
class AdminNavTest < ActionDispatch::IntegrationTest
  test "admin menu lists all destinations including Plan" do
    admin = User.create!(email_address: "nav-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(admin)
    get admin_dashboard_path
    assert_response :success
    %w[Plan Dashboard Track Posts Videos Scrapers Users Agents Kitchen Chat Lab Notifications].each do |label|
      assert_match %r{>#{label}<}, response.body, "menu should include #{label}"
    end
    assert_match "Visitor Map", response.body
    assert_match "AI Costs", response.body
  end
end

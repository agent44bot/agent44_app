require_relative "system_test_helper"
require_relative "pages/base_page"
require_relative "pages/kitchen_page"

class NykitchenSystemTest < SystemTestCase
  setup do
    @kitchen = KitchenPage.new(@page, BASE_URL) if @page

    # /nykitchen/list now requires sign-in; create a member admin so the
    # post-pivot tests can exercise the agents-hub list view.
    @admin = User.find_or_create_by!(email_address: "nyk-sys@nyk.test") do |u|
      u.role     = "admin"
      u.password = "password123"
    end
    ws = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @admin }
    ws.memberships.find_or_create_by!(user: @admin) { |m| m.role = "owner" }
  end

  def sign_in_admin
    @page.goto("#{BASE_URL}/session/new")
    @page.fill("input[name='email_address']", @admin.email_address)
    @page.fill("input[name='password']",      "password123")
    @page.click("button[type='submit']")
    sleep 0.5
  end

  test "kitchen list page loads and shows event cards" do
    sign_in_admin
    @kitchen.visit

    assert_equal 200, @kitchen.response_status
    assert_match(/NY Kitchen/i, @kitchen.body_text)
    assert @kitchen.cards.size > 0, "Expected event cards on the page"
  end

  test "filter chips work" do
    sign_in_admin
    @kitchen.visit
    @kitchen.expand_filter

    chip = @kitchen.filter_chip("instock")
    assert chip, "Expected 'Available' filter chip on the page"

    chip.click
    sleep 0.3

    @kitchen.visible_cards.each do |card|
      assert_equal "instock", card.get_attribute("data-status"),
        "Expected only 'instock' cards after filtering"
    end
  end

  test "class search filters the list to matching classes" do
    sign_in_admin
    @kitchen.visit

    first = @kitchen.cards.first
    skip "no seeded classes to search" unless first
    # Pick a distinctive word from a real class to search for.
    term = first.get_attribute("data-search-text").to_s.split(/\s+/).find { |w| w.length >= 4 }
    skip "no searchable term" unless term

    @kitchen.search(term)
    visible = @kitchen.visible_cards
    assert visible.size > 0, "Expected at least one class to match #{term.inspect}"
    visible.each do |card|
      assert_includes card.get_attribute("data-search-text").to_s, term,
        "Every visible card should contain the search term"
    end
  end

  test "admin kitchen redirects to nykitchen" do
    @page.goto("#{BASE_URL}/admin/kitchen")
    assert_equal "#{BASE_URL}/nykitchen", @page.url
  end

  test "home page loads" do
    home = BasePage.new(@page, BASE_URL)
    home.visit("/")
    assert_equal 200, home.response_status
    assert home.title.present?, "Expected home page to have a title"
  end

  test "jobs page loads" do
    jobs = BasePage.new(@page, BASE_URL)
    jobs.visit("/jobs")
    assert_equal 200, jobs.response_status
    assert jobs.body_text.present?, "Expected content on jobs page"
  end
end
